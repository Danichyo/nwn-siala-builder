defmodule BuildCalculatorWeb.BuildViewLiveTest do
  @moduledoc """
  The read-only screen: the one a shared link lands on.
  """
  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}
  alias BuildCalculatorWeb.Builder.{Gaps, Labels}

  setup do
    ruleset = Data.ruleset!()

    build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :dwarf,
        alignment: :lawful_good,
        base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
        levels: List.duplicate(:fighter, 20) ++ List.duplicate(:weapon_master, 21),
        ability_increases: %{4 => :str, 8 => :str},
        feats: %{1 => %{:general => :toughness, {:class_bonus, :fighter} => :power_attack}},
        skills: %{1 => %{discipline: 4, tumble: 1}}
      )

    %{ruleset: ruleset, build: build, code: Encoding.encode(build)}
  end

  # ⚠️ Разбор итогов с 10.08.2026 (задача 3.24) — СПИСОК, а не строка: имя
  # слагаемого и его число лежат в разных `span` внутри одного `.t`, потому что
  # числа выровнены в столбик по правому краю. Утверждения ниже про «в разборе
  # названо `Fighter 20 (полный) 20`» от этого не устарели по смыслу — устарел
  # только способ их проверить: между именем и числом теперь стоит тег, а не
  # пробел. Плоское `render(…) =~ "…"` спотыкалось бы на любой вёрстке разбора,
  # поэтому теги сводятся к пробелам, и утверждение остаётся тем же:
  # «имя и число стоят рядом, в одном слагаемом».
  defp caption_text(html) do
    html
    |> String.replace(~r{<[^>]*>}, " ")
    |> String.replace(~r{\s+}, " ")
    |> String.trim()
  end

  # Задача 3.147: `○` по умолчанию скрыт (решение Dan — «выключить по
  # дефолту, чтобы разгрузить UI», тот же довод и тот же дефолт, что у
  # конструктора, 3.146). Тесты этого файла ниже, писанные ДО переключателя,
  # проверяют, что выданное классом рендерится ВЕРНО — это по-прежнему нужно
  # знать, только теперь после явного клика по `#view-granted-checkbox`
  # (тот же приём, что в `build_view_guide_test.exs`, — общего support-модуля
  # под настолько маленькие LiveView-хелперы в проекте нет, каждый файл
  # держит свой, как уже делают `caption_text/1` и `render_assigns/2` рядом).
  defp open_with_granted(conn, path) do
    {:ok, view, _html} = live(conn, path)
    view |> element("#view-granted-checkbox") |> render_click()
    {:ok, view, render(view)}
  end

  # Задача 3.45: `Diamond soul` — единственная выдача класса на этом уровне
  # монаха, и ровно на 12-м Dan решил показывать карточку SR
  # (`Summary.spell_resistance_visible?/1`).
  defp monk_up_to(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:monk, levels),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
    )
  end

  # Задача 3.88: у гэпов ДАННЫХ (в отличие от гэпов этого билда) баннер
  # гейтится `@gaps.data_real_count > 0`, а живые данные сегодня дают 0
  # (задача 3.86) — единственный честный способ проверить, что ворота
  # ОТКРЫВАЮТСЯ, это синтетический ruleset с наведённой дырой, а не
  # надежда, что живые данные когда-нибудь снова станут ненулевыми
  # (постановка задачи предупреждает ровно об этой ловушке). Rulesets are
  # compiled in (`BuildCalculator.Data`, «compiled into the beam»): реальный
  # `live/2` не может подхватить ad-hoc ruleset по строке версии, которой
  # нет в `Data.versions/0`. Вместо этого шаблон (`BuildViewLive.render/1`,
  # авто-сгенерированная функция co-located `.html.heex`) вызывается
  # напрямую с одним переопределённым assign'ом; остальные — из ДЕЙСТВИТЕЛЬНО
  # смонтированной, рабочей страницы (`:sys.get_state/1` — приём, которым
  # `AGENTS.md` уже разрешает пользоваться для LiveView-тестов, здесь
  # применённый для чтения состояния вместо синхронизации).
  defp render_assigns(view, overrides) do
    %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)

    assigns
    |> Map.merge(overrides)
    |> BuildCalculatorWeb.BuildViewLive.render()
    |> rendered_to_string()
  end

  describe "rendering a shared code" do
    test "the screen opens straight from the code in the path", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#build-view")
      assert render(element(view, "#view-title")) =~ "Fighter 20"
      assert render(element(view, "#view-title")) =~ "Weapon master 21"
      assert render(element(view, "#view-subtitle")) =~ "Гном (Dwarf)"
      assert render(element(view, "#view-subtitle")) =~ "41 / 41"
    end

    # ⚠️ Задача 3.148 (31.08.2026): раньше здесь стояло `assert has_element?(view,
    # "#view-gaps")` — блок был непустым безусловно (снятая строка «числа ниже —
    # база билда, без экипировки»). У ЭТОГО билда нет ни настоящих дыр данных,
    # ни своих гэпов (`data_real_count == 0`, `build_count == 0`), так что
    # `#view-gaps` с гейтом теперь молчит по праву — а «билд без вещей» видно
    # рекомендацией, которая на пустом билде тем более уместна.
    test "an empty build still renders without the totals", %{conn: conn, ruleset: ruleset} do
      code = Encoding.encode(Build.new(ruleset_version: ruleset.version))
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert render(element(view, "#view-title")) =~ "Пустой билд"
      refute has_element?(view, "#view-stats")
      assert has_element?(view, "#view-gear-hint")
    end

    test "a mangled code says so and offers a way forward, not a 500", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/1.definitely-not-a-code")

      assert has_element?(view, "#view-error")
      assert render(element(view, "#view-error-message")) =~ "битая"
      assert has_element?(view, "#view-error-new")
    end
  end

  describe "totals show the arithmetic behind them" do
    # ⚠ Задача 3.16 заменила подпись «20 на 20-м + 10 эпических» разбором по
    # классам. Смысл теста от этого не сместился, а расширился: раньше он
    # требовал, чтобы у BAB было названо ДВЕ половины, теперь — чтобы был
    # назван каждый класс, включая тот, чьи уровни отброшены.
    test "BAB names every class and the epic term", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # Fighter 20 first, then 21 levels of Weapon Master: base attack is frozen
      # at 20 and the epic bonus is added on top (CLAUDE.md §3).
      caption = caption_text(render(element(view, "#view-stat-bab")))

      assert caption =~ "Fighter 20 (полный) 20"

      # 🔴 Ноль назван вслух, а не пропущен молча: двадцать один уровень мастера
      # оружия в базовую атаку не пошёл вообще, и подпись обязана это сказать —
      # иначе разбор молчит ровно про то, из-за чего игрок теряет полбилда.
      assert caption =~ "Weapon master 0 из 21"
      assert caption =~ "эпик +11"
    end

    test "the rule behind the dropped levels is spelled out, not implied", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      note = render(element(view, "#view-counted-window"))

      assert note =~ "первые 20 уровней"
      assert note =~ "порядок взятия классов"
    end

    test "a build inside the window says nothing about it", %{conn: conn, ruleset: ruleset} do
      # Положительный контроль к тесту выше: правило печатается не всегда, а
      # только там, где оно что-то отняло. У воина 10-го уровня отбирать нечего.
      code =
        Encoding.encode(
          Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:fighter, 10))
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-stat-bab")
      refute has_element?(view, "#view-counted-window")
    end

    test "attacks per round explain that they are frozen at level 20", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      caption = render(element(view, "#view-stat-apr"))

      assert caption =~ "от BAB 20 за первые 20 уровней"

      # Ровно та строка, ради которой подпись переписана: BAB на экране 31,
      # а атаки считаются от 20, и раньше об этом не говорилось вслух.
      assert caption =~ "эпик (+11) атак не добавляет"
    end

    # 🔴 Задача 3.22: разбор AB одинаков на ДВУХ экранах, и это проверяется
    # сравнением, а не двумя списками ожиданий. Оба читают `Summary.ab_terms/2`,
    # но у экрана просмотра это строка-подпись, а у конструктора — термы поп-апа,
    # и разъехаться они могут молча: два разбора одного числа на двух экранах —
    # худший исход этой задачи.
    #
    # ⚠️ Фикстура здесь СВОЯ, с вещами: у билда файла вещей нет вовсе, а именно
    # они и есть предмет задачи. Сила 16 + 2 (уровни 4 и 8) = 18 голыми (+4),
    # с вещами +12 → 30 (+10).
    test "разбор AB на просмотре и в конструкторе — один и тот же", %{
      conn: conn,
      build: %Build{} = build
    } do
      code = Encoding.encode(%Build{build | gear: Gear.new(abilities: %{str: 12})})

      {:ok, viewer, _html} = live(conn, ~p"/b/#{code}")
      {:ok, builder, _html} = live(conn, ~p"/?b=#{code}")

      caption = caption_text(render(element(viewer, "#view-stat-ab")))

      terms =
        builder
        |> element("#stat-attack_bonus")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#stat-attack_bonus .stat-pop-trigger")
        |> LazyHTML.attribute("data-pop-terms")
        |> hd()
        |> Jason.decode!()

      # Слитый терм назван обоими: +10, а не +4 (голый) и не двумя строками.
      assert %{"label" => "STR", "value" => "+10"} in terms
      refute Enum.any?(terms, &(&1["label"] in ["вещи", "с вещей"]))

      # И главное — разбор экрана просмотра собран ИЗ ЭТИХ ЖЕ термов, В ТОМ ЖЕ
      # ПОРЯДКЕ. ⚠️ Порядок здесь не косметика: он называет сторону капа — сначала
      # то, что потолок режет, потом сам срез, потом лежащее поверх (CLAUDE.md §3).
      # Разделителя « + » между слагаемыми больше нет: с 10.08.2026 разбор — список,
      # и каждое слагаемое стоит своей строкой, а числа выровнены в столбик.
      sentence = Enum.map_join(terms, " ", &"#{&1["label"]} #{&1["value"]}")

      assert caption =~ sentence
      refute caption =~ "вещи"
    end

    # Запрос Dan 08.08.2026. ⚠️ Фикстура этого файла — Гном, воин 20 / мастер
    # оружия 21, то есть чистый **воин Сагры** по составу, и одновременно НЕ
    # адровец (мастер оружия в Адру не входит). Один билд проверяет обе стороны
    # правила сразу: перепутай списки групп — и флажок будет не тот.
    test "флажки групп классов стоят над итогами", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-stats #view-class-groups")
      assert render(element(view, "#view-class-group-sagra_warriors")) =~ "Воины Сагры"
      refute has_element?(view, "#view-class-group-adra_warriors")

      # Пояснение называет классы по-английски (§4), а правило чистоты словами:
      # человек, пришедший по ссылке, состава билда наизусть не знает.
      title = render(element(view, "#view-class-group-sagra_warriors"))
      assert title =~ "Barbarian"
      assert title =~ "один уровень любого другого отменяет"
    end

    # ⚠️ И то же самое, увиденное с другой стороны: билд из классов Адры даёт
    # флажок Адры и НЕ даёт Сагры, а помечен допущением — правило чистоты Адры
    # не описано никем. Взято с реальной страницы «Паладин Адры» (revid 19670):
    # паладин 38 / монах 1 / чемпион Торма 1.
    test "билд Адры получает свой флажок с пометкой допущения", %{conn: conn, ruleset: ruleset} do
      adra =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :lawful_good,
          base_abilities: %{str: 14, dex: 10, con: 12, int: 14, wis: 14, cha: 14},
          levels: List.duplicate(:paladin, 38) ++ [:monk, :champion_of_torm]
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(adra)}")

      assert has_element?(view, "#view-class-group-adra_warriors[data-assumed='1']")
      refute has_element?(view, "#view-class-group-sagra_warriors")
    end

    # ⚠️ Раньше тест требовал слово «база» и на нём же и заканчивался. Задача
    # «разбор сейвов по классам» заменила единственный терм «база» термом на
    # каждый класс, и смысл теста от этого не сместился, а расширился — как
    # у BAB в 3.16: теперь обязан быть назван каждый класс, включая тот, чьи
    # уровни в сейв не пошли.
    test "each save names every class, the epic term and the ability", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # Fighter 20, потом 21 уровень мастера оружия: у воина Fort «высокий»
      # (12 на 20-м), у мастера оружия «низкий» — но ни то, ни другое уже
      # не считается, потому что все его уровни за окном.
      for {id, ability, fighter} <- [
            {"fort", "CON", "Fighter 20 (высокий) 12"},
            {"ref", "DEX", "Fighter 20 (низкий) 6"},
            {"will", "WIS", "Fighter 20 (низкий) 6"}
          ] do
        caption = caption_text(render(element(view, "#view-stat-#{id}")))

        assert caption =~ fighter

        # 🔴 Ноль назван вслух: двадцать один уровень мастера оружия не дал
        # ни одному из трёх сейвов ничего, и подпись обязана это сказать.
        assert caption =~ "Weapon master 0 из 21"
        assert caption =~ ability
        assert caption =~ "эпик +10"
      end
    end

    # ⚠️ Долг из AGENT_QUEUE §7 («Разбор характеристик на экране ПРОСМОТРА»,
    # найден задачей 3.1): раньше здесь стояло голое «старт → финал» без
    # единого слагаемого. Теперь под значением — та же подпись-каскад, что
    # уже печатают AB/AC/сейвы/HP этого экрана (`terms_caption/1`, 3.6), а не
    # поп-ап конструктора: смотреть тут нечего выбирать, значит нечего
    # прятать за наведением (см. moduledoc `BuildViewLive`).
    test "у характеристики со слагаемыми видно и итог, и из чего он собрался", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # 16 bought, +2 at levels 4 and 8, dwarves get nothing to strength.
      str = render(element(view, "#view-ability-str"))

      assert str =~ "18"
      assert str =~ "+4"

      # ⚠️ Не просто «сумма сходится» (HANDOFF: этого не ловит остаточный
      # терм) — назван каждый слагаемый со своей подписью.
      assert str =~ "база"
      assert str =~ "16"
      assert str =~ "уровни"
      assert str =~ "+2"
    end

    # Положительный контроль к тесту выше и к «нулевые термы молчат» ниже:
    # у характеристики, которую билд вообще не трогал (ни расой — гном
    # трогает только CON/CHA, — ни уровнями, ни вещами), разбора нет вовсе:
    # единственный терм «база» не говорит того, чего число рядом не сказало
    # уже само.
    test "у характеристики без единого лишнего слагаемого нет строки разбора", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute has_element?(view, "#view-ability-int .from")
      int = render(element(view, "#view-ability-int"))
      assert int =~ "10"
      refute int =~ "база"
    end

    # AGENT_QUEUE §7: у Ученика красного дракона экран печатал «12 → 20» и не
    # объяснял ни цифры — восемь очков силы появлялись из воздуха, хотя ядро
    # их уже считало и называло поимённо (задача 3.1, `own_terms`).
    test "у Ученика красного дракона разбор называет источник прибавки", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: List.duplicate(:sorcerer, 2) ++ List.duplicate(:red_dragon_disciple, 10),
          base_abilities: %{str: 12, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      str = render(element(view, "#view-ability-str"))

      assert str =~ "20"
      assert str =~ "база 12"
      assert str =~ "Dragon abilities +8"
    end
  end

  # Вторая рука (задача 3.132, Dan: «Для второй руки отдельную строку, мешать
  # не надо»). ⚠️ «Атаки — через слеш» было первой формой числа атак и не
  # дожило до задачи 3.133 (Dan, замечание 1: «показывает 4/1, но в
  # реальности это 4 атаки основной рукой и одна атака второй») — теперь
  # у второй руки своя карточка «Атак второй руки», тем же приёмом, что
  # у «AB второй руки».
  describe "вторая рука на экране просмотра (задачи 3.132/3.133)" do
    defp dual_wield_view_build(ruleset) do
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:fighter, 20),
        base_abilities: %{str: 18, dex: 14, con: 14, int: 10, wis: 10, cha: 10},
        gear:
          Gear.new(
            weapon: :katana,
            off_hand_weapon: :mace,
            feats: [:siala_blade_proficiency, :siala_hammer_proficiency]
          )
      )
    end

    # ⚠️ Строка «Атак / раунд» несёт слеш в САМОЙ ПОДПИСИ безусловно —
    # `render(element(...)) =~ "/"` на всём узле зеленел бы и без задачи
    # 3.132, поэтому сравнивается именно ЗНАЧЕНИЕ (`.v`), как и в конструкторе.
    defp apr_value(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#view-stat-apr .v")
      |> LazyHTML.text()
      |> String.trim()
    end

    # Положительный контроль: билд из фикстуры файла бьётся одним оружием, и
    # у него нет ни одной из карточек второй руки, ни расхождения
    # «Атак / раунд» со слешем.
    test "нет карточек второй руки у персонажа с одним оружием", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute has_element?(view, "#view-stat-off_hand_ab")
      refute has_element?(view, "#view-stat-off_hand_apr")
      refute apr_value(view) =~ "/"
    end

    test "карточка «AB второй руки» называет своё число и свой разбор", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = dual_wield_view_build(ruleset)
      stats = Rules.compute(build, ruleset)
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-stat-off_hand_ab")
      card = render(element(view, "#view-stat-off_hand_ab"))

      assert card =~ "AB второй руки"
      assert card =~ "+#{stats.off_hand.attack_bonus}"

      # Разбор обязан назвать штраф стиля — иначе слагаемые не сойдутся со
      # своим же итогом (см. `Summary.off_hand_ab_terms/2`).
      assert card =~ "бой двумя оружиями"
    end

    # 🔴 Задача 3.133 (замечание 1): «Атак / раунд» остаётся одним числом
    # главной руки, а вторая рука печатает своё число собственной карточкой
    # «Атак второй руки» — той же формой, что уже разведена «AB второй руки».
    test "«Атак / раунд» остаётся одним числом, «Атак второй руки» — своя карточка", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = dual_wield_view_build(ruleset)
      stats = Rules.compute(build, ruleset)
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      refute apr_value(view) =~ "/"
      assert apr_value(view) == "#{stats.attacks_per_round}"

      assert has_element?(view, "#view-stat-off_hand_apr")

      off_apr =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#view-stat-off_hand_apr .v")
        |> LazyHTML.text()
        |> String.trim()

      assert off_apr == "#{stats.off_hand.attacks_per_round}"
    end

    # 🔴 Тот же довод, что у «разбор AB на просмотре и в конструкторе — один
    # и тот же»: оба экрана читают `Summary.off_hand_ab_terms/2`, а не два
    # независимых текста, которые могут молча разойтись.
    test "разбор AB второй руки на просмотре и в конструкторе — один и тот же", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = dual_wield_view_build(ruleset)
      code = Encoding.encode(build)

      {:ok, viewer, _html} = live(conn, ~p"/b/#{code}")
      {:ok, builder, _html} = live(conn, ~p"/?b=#{code}")

      caption = caption_text(render(element(viewer, "#view-stat-off_hand_ab")))

      terms =
        builder
        |> element("#stat-off_hand_ab")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#stat-off_hand_ab .stat-pop-trigger")
        |> LazyHTML.attribute("data-pop-terms")
        |> hd()
        |> Jason.decode!()

      assert Enum.any?(terms, &(&1["label"] == "бой двумя оружиями"))
      sentence = Enum.map_join(terms, " ", &"#{&1["label"]} #{&1["value"]}")

      assert caption =~ sentence
    end
  end

  describe "SR (сопротивление заклинаниям) — задача 3.45, заход 2" do
    # 🔴 Не карточка «SR 0» / «SR ?» — карточки нет ВООБЩЕ, тот же критерий,
    # что у «AC в шмоте» до появления вещей: Dan просил строку только для
    # билдов с 12+ уровнями монаха.
    test "монах 11 не показывает карточку SR", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(monk_up_to(ruleset, 11))}")

      refute has_element?(view, "#view-stat-spell_resistance")
    end

    test "монах 12 показывает карточку SR с разбором списком", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(monk_up_to(ruleset, 12))}")

      card = caption_text(render(element(view, "#view-stat-spell_resistance")))

      # Видимое число — итоговая величина без знака («22»), не разбор.
      assert card =~ "22"

      # Разбор — списком, тем же приёмом, что у HP/AB/AC/сейвов этого экрана
      # (задача 3.24): «Diamond soul +22», без имени класса и его уровня —
      # сознательное решение ядра (задача 3.45, заход 1).
      assert card =~ "Diamond soul +22"
      refute has_element?(view, "#view-stat-spell_resistance[data-unknown='1']")
    end

    # 🔴 Задача 3.22/3.45: разбор SR одинаков на ДВУХ экранах — оба читают
    # `Summary.spell_resistance_terms/2`, и разъехаться они могут молча.
    test "разбор SR на просмотре и в конструкторе — один и тот же список", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        ruleset
        |> monk_up_to(41)
        |> Build.put_feat(21, :general, :improved_spell_resistance)
        |> Build.put_feat(24, :general, :improved_spell_resistance)

      code = Encoding.encode(build)

      {:ok, viewer, _html} = live(conn, ~p"/b/#{code}")
      {:ok, builder, _html} = live(conn, ~p"/?b=#{code}")

      caption = caption_text(render(element(viewer, "#view-stat-spell_resistance")))

      terms =
        builder
        |> element("#stat-spell_resistance")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#stat-spell_resistance .stat-pop-trigger")
        |> LazyHTML.attribute("data-pop-terms")
        |> hd()
        |> Jason.decode!()

      # 41 + 10 = 51 (Diamond soul) + 2 × 2 = 4 (Improved spell resistance).
      assert %{"label" => "Diamond soul", "value" => "+51"} in terms
      assert %{"label" => "Improved spell resistance ×2", "value" => "+4"} in terms

      sentence = Enum.map_join(terms, " ", &"#{&1["label"]} #{&1["value"]}")
      assert caption =~ sentence
    end

    # ⚠️ Ворота — уровни МОНАХА, а не владение `Diamond soul`: фит можно
    # объявить с вещи, и тогда ядро честно посчитает `spell_resistance: 10`
    # даже у воина — но карточку про это Dan не просил.
    test "у не-монаха с Diamond soul с вещи карточки нет", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          gear: Gear.new(feats: [:diamond_soul])
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      refute has_element?(view, "#view-stat-spell_resistance")
    end

    # Экран просмотра ничего не прячет за кликом (CLAUDE.md §6): оговорка про
    # предметы обязана быть видна сразу — как и признание о неполноте правил
    # в целом.
    test "оговорка про предметы видна на экране просмотра без единого клика", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(monk_up_to(ruleset, 12))}")

      assert render(element(view, "#view-gaps")) =~ "SR с предметов не считаем"
    end

    # ⚠️ Задача 3.148: `render(element(view, "#view-gaps"))` тут больше не
    # годится — у монаха 11 нет ни настоящих дыр данных, ни своих гэпов
    # билда (SR-то и не считается вовсе, карточки нет), так что `#view-gaps`
    # с новым гейтом не рендерится совсем, и запрос элемента, которого нет,
    # падает раньше, чем `refute` до него дойдёт. Проверяем страницу целиком —
    # утверждение то же самое («фразы нет нигде»), а элемент под ним больше
    # не обязан существовать.
    test "у монаха 11 оговорки про предметы нет — вопрос не возник", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(monk_up_to(ruleset, 11))}")

      refute render(view) =~ "SR с предметов не считаем"
    end
  end

  describe "what the build took" do
    # 🔴 Правка Dan 10.08.2026: «перепись фитов можно удалить, будем их в гиде
    # смотреть». Секция «Фиты и навыки» стала «Навыки», а фиты остались ровно
    # в одном месте — в гиде.
    #
    # ⚠️ 03.09.2026 (задача 3.175) — Dan попросил список фитов ОБРАТНО, но не
    # тот же самый: «просто список берущихся фитов… раз попросили можно
    # и отдельно список фитов добавить». Новый `#view-feats` компактнее
    # снятого (одна строка «глиф + имя + уровень», без разбора и без
    # выданного классом), поэтому здесь `assert` там, где раньше был `refute` —
    # но два довода старого теста остаются верными и проверяются ниже
    # так же, как раньше: навыки живут в своей секции, а гид — единственное
    # место, где видно и выбранное, и выданное классом ВМЕСТЕ.
    test "список фитов внизу компактен, навыки и гид на месте", %{conn: conn, code: code} do
      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{code}")

      # Список — по именам, а не по счётчику без имён (тот же довод, что убрал
      # плашку «от класса ×N» с карточки класса 02.08.2026). Индекс в id —
      # позиция фита в СЛОТАХ уровня (`Build.slot_order/1`): `:general`
      # сортируется раньше `{:class_bonus, :fighter}`, поэтому Toughness — 0,
      # Power attack — 1.
      assert has_element?(view, "#view-feats")
      assert render(element(view, "#view-feats-count")) =~ "Фиты — 2"
      assert has_element?(view, "#view-feats-legend")
      assert render(element(view, "#view-feat-1-0-toughness")) =~ "Toughness"
      assert render(element(view, "#view-feat-1-1-power_attack")) =~ "Power attack"

      # ⚠️ Выданное классом («берущихся», не «все») в этот список НЕ идёт —
      # решение 3.175, тот же довод, что уже отверг общий счётчик «Фиты — N»
      # у старой переписи (складывал оба источника и не отвечал ни на «что
      # получу», ни на «что решать», CLAUDE.md §6). Выданное смотрят через
      # `○`-переключатель гида — он для этого и существует.
      refute has_element?(view, "#view-granted-1-toughness")

      # Положительный контроль №1: секция жива и в ней навыки.
      assert has_element?(view, "#view-picks #view-skills")
      assert has_element?(view, "#view-skills-count")
      assert render(element(view, "#view-skill-discipline")) =~ "4"
      # Tumble is cross-class for this build, which doubled the price.
      assert has_element?(view, "#view-skill-tumble[data-cross='1']")

      # Положительный контроль №2: те же фиты видны в гиде — и выбранные,
      # и выданные классом, по именам, а не по счётчику.
      assert render(element(view, "#view-guide-level-1")) =~ "Toughness"
      assert render(element(view, "#view-guide-level-1")) =~ "Power attack"
      assert has_element?(view, "#view-guide-level-1-granted-toughness")
    end

    # ★ был виден ТОЛЬКО в переписи: гид печатал `✦` любому фиту. Вместе
    # с переписью эта разница исчезла бы с экрана вовсе, поэтому глиф переехал
    # в гид, а легенда его назвала.
    #
    # ⚠️ Задача 3.176 расширила тест до ТРЁХ глифов, а не двух, и заодно
    # заменила его прежний «обычный» пример. `Power attack` в этой фикстуре
    # взят `{:class_bonus, :fighter}` (см. `setup`), а не общим слотом —
    # раньше это не имело значения (глиф читался ПО ФИТУ,
    # `ruleset.feats[id].epic?`), а после правки читается ПО СЛОТУ
    # (`Labels.slot_glyph/1`, тот же читатель, что у лестницы конструктора),
    # и тот же `Power attack` стал `⚔`, а не `✦`. Это и есть цель правки,
    # а не регрессия: до неё гид рисовал бонусный фит общим глифом и не
    # отличал его от общего слота вовсе. `Iron will` — новый пример на
    # ПРАВДА общий слот (уровень 3, ни один класс его не выдаёт даром,
    # `granted_by: MapSet.new([])`), чтобы «обычный ✦» осталось проверено
    # хоть чем-то.
    test "эпический, бонусный и обычный фит в гиде помечены разными глифами — ★, ⚔, ✦", %{
      conn: conn,
      build: build
    } do
      # `Epic toughness` эпический и на 21-м уровне легален (проверено
      # `Rules.illegal_feats/2`: пусто), `Power attack` — бонусный слот
      # Fighter'а, `Iron will` — обычный общий слот. Три разных фита нарочно:
      # совпади хоть два глифа, тест зеленел бы вслепую.
      build =
        build
        |> Build.put_feat(21, :general, :epic_toughness)
        |> Build.put_feat(3, :general, :iron_will)

      code = Encoding.encode(build)
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      epic = render(element(view, "#view-guide-level-21 .pick", "Epic toughness"))
      assert epic =~ "★"
      refute epic =~ "✦"
      refute epic =~ "⚔"

      bonus = render(element(view, "#view-guide-level-1 .pick", "Power attack"))
      assert bonus =~ "⚔"
      refute bonus =~ "✦"
      refute bonus =~ "★"
      assert has_element?(view, "#view-guide-level-1 .pick[data-bonus='1']", "Power attack")

      plain = render(element(view, "#view-guide-level-3 .pick", "Iron will"))
      assert plain =~ "✦"
      refute plain =~ "★"
      refute plain =~ "⚔"
      refute has_element?(view, "#view-guide-level-3 .pick[data-bonus='1']", "Iron will")

      legend = render(element(view, "#view-guide-legend"))
      assert legend =~ "эпический фит"
      assert legend =~ "бонусный фит"
    end

    # Просьба Dan 10.08.2026: «может нам раскрасить строки таблицы в цвет
    # класса? Сейчас однотонно». Проверяется механизм, а не краска: оттенок
    # приезжает переменной `--h` (та же `Palette.style/1`, что у лестницы
    # конструктора), поэтому обе темы работают сами.
    test "строка гида несёт оттенок своего класса", %{conn: conn, code: code, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      fighter = BuildCalculatorWeb.Builder.Palette.hue(:fighter)
      wm = BuildCalculatorWeb.Builder.Palette.hue(:weapon_master)
      assert fighter != wm, "оттенки классов совпали — таблица Palette сломана"

      assert has_element?(view, "#view-guide-level-1[style*='--h: #{fighter}']")
      assert has_element?(view, "#view-guide-level-22[style*='--h: #{wm}']")

      # Престиж — приглушённым кольцом, и через СВОЙ атрибут: общий `data-prc`
      # подменял бы `--cls-s` всему поддереву строки, а там на той же машинерии
      # живут оттенки характеристик.
      assert ruleset.classes[:weapon_master].prestige?
      assert has_element?(view, "#view-guide-level-22[data-class-prc='1']")
      refute has_element?(view, "#view-guide-level-22[data-prc='1']")
      refute has_element?(view, "#view-guide-level-1[data-class-prc='1']")
    end

    # Задача 3.169: `.cls` теперь обрезает однословные имена (было
    # `overflow: visible` без точки переноса — «Shadowdancer», 92.9px,
    # красилось поверх соседней колонки на 74px-треке, а не помещалось
    # в него, любая ширина ≥621px). Разметку тесты не видят по построению
    # (`Phoenix.LiveViewTest` не считает layout — сам замер переполнения
    # живёт в CDP, не здесь), но `title` с полным именем — обычный HTML-
    # атрибут, и его исчезновение при будущей правке — тихая регрессия,
    # которую стоит ловить дёшево.
    #
    # ⚠️ `WM` — сокращение (`Labels.class_short/2` инициалит многословные
    # имена), поэтому `title` обязан назвать целиком то, что видимый текст
    # сократил: без этого подсказка при наведении повторяла бы «WM», а не
    # отвечала на «а что такое WM».
    test "у `.cls` есть title с полным именем класса", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      fighter = element(view, "#view-guide-level-1 .cls")
      assert render(fighter) =~ "Fighter"
      assert has_element?(view, "#view-guide-level-1 .cls[title='Fighter']")

      # ⚠️ Сравнение через `caption_text/1`, а не `render(...) =~ "WM"`: сырой
      # HTML несёт полное имя ДВАЖДЫ, вторым разом внутри `title="…"` самого
      # тега, и `=~` совпал бы с обоими сразу — только очищенный от тегов
      # текст доказывает, что ВИДИМОЕ содержимое сокращено, а не повторяет
      # атрибут.
      wm = element(view, "#view-guide-level-21 .cls")
      assert wm |> render() |> caption_text() == "WM"
      assert has_element?(view, "#view-guide-level-21 .cls[title='Weapon master']")
    end

    # ⚠️ Долг §7 AGENT_QUEUE.md, «шестая пятёрка» — тот же инвариант, что
    # у лестницы конструктора (`builder_live_test.exs`), и он про ПРИЧИНУ, а не
    # про имя атрибута: правило `[data-prc="1"]` подменяет `--cls-s`/`--cls-l`
    # всему поддереву, поэтому элемент с этим атрибутом не имеет права содержать
    # другого потребителя `--h` — его оттенок останется своим, а насыщенность
    # и светлота станут престижными.
    #
    # Проверяется на этом экране отдельно, потому что баг здесь был свой: гид
    # строки — контейнер, внутри которого живёт `▲ STR` со своим оттенком.
    # Что этим НЕ проверяется — сами `rgb(...)`: сойдутся ли правила в задуманный
    # цвет, видно только замером в браузере.
    test "ни один `data-prc` не накрывает чужой оттенок", %{conn: conn, build: build} do
      # ⚠️ Прибавка к характеристике на ПРЕСТИЖ-уровне: у фикстуры они обе
      # на воинских (4 и 8), а без такой строки положительный контроль ниже
      # проверял бы отсутствие вёрстки, а не её безвредность.
      %Build{} = build = build
      on_prestige = %Build{build | ability_increases: Map.put(build.ability_increases, 24, :str)}

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(on_prestige)}")

      document = view |> render() |> LazyHTML.from_fragment()
      leaked = LazyHTML.query(document, ~s([data-prc] [style*="--h"]))

      assert Enum.count(leaked) == 0, inspect(leaked)

      # Положительный контроль: конструкция «атрибут на контейнере, чужой оттенок
      # внутри» на странице ЕСТЬ — под своим именем, где она безвредна.
      assert Enum.count(LazyHTML.query(document, ~s([data-class-prc] [style*="--h"]))) > 0
    end

    # ⚠️ Ранги — это не то, чем меряется персонаж в игре. Строка обязана
    # показывать оба числа так, чтобы их нельзя было спутать.
    test "у навыка видно и ранги, и значение, и из чего оно собралось", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # Discipline: 4 ранга + STR +4 (16 куплено, +1 на 4-м и 8-м) = 8.
      # Числа намеренно разные — совпади они, тест проходил бы вслепую.
      row = render(element(view, "#view-skill-discipline"))

      assert row =~ "4 (8)"
      assert row =~ "4 р."
      assert row =~ "STR +4"

      # ⚠️ Знака у значения быть не должно: «4 (+8)» читается как «4 ранга
      # и ещё восемь сверху», хотя 8 — это и есть весь результат.
      refute row =~ "(+8)"

      # Подпись у колонки: без неё два числа в строке — ребус.
      assert render(element(view, "#view-skills-legend")) =~ "ранги (значение"
    end

    # 🔴 Здесь стояло «навык без ключевой характеристики показывает ?»: у
    # Алхимии её не называла ни одна вики. **Замер Dan 17.08.2026 (кейс P1)
    # назвал мудрость**, и у экрана просмотра не осталось ни одного навыка,
    # который печатал бы «?»: ruleset здесь приходит из приложения
    # (`Data.ruleset!/1`, вкомпилирован), подменить его нельзя, и синтетический
    # свидетель сюда не дотягивается.
    #
    # ⚠️ Поэтому тест перевёрнут в положительный, а САМА печать «?» проверяется
    # слоем ниже, где ruleset передаётся аргументом: `Summary.skill_rows/3`
    # (`summary_test.exs`, «навык без ключевой характеристики печатает «?»»)
    # и экспорт. Шаблон между ними ровно один `data-unknown`, и он общий
    # с другими числами экрана, у которых отказ живой.
    test "навык шарда показывает число, а не «?» — характеристика названа", %{
      conn: conn,
      ruleset: ruleset,
      build: %Build{} = build
    } do
      code = Encoding.encode(%Build{build | skills: %{1 => %{alchemy: 3, discipline: 4}}})
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      row = render(element(view, "#view-skill-alchemy"))

      refute row =~ "(?)"
      refute row =~ "характеристика не названа"
      refute has_element?(view, "#view-skill-alchemy[data-unknown='1']")

      # Число и его разбор названы: 3 ранга плюс мудрость персонажа фикстуры.
      assert row =~ "3 р."
      assert row =~ "WIS"
      assert ruleset.skills[:alchemy].key_ability == :wis
    end

    test "the levelling guide covers every level, in two reading columns", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-guide-level-1")
      assert has_element?(view, "#view-guide-level-41")
      # Two columns of consecutive levels: 1..21 then 22..41.
      assert has_element?(view, "#view-guide-0 #view-guide-level-21")
      assert has_element?(view, "#view-guide-1 #view-guide-level-22")
      assert render(element(view, "#view-guide-level-1")) =~ "Toughness"
      assert render(element(view, "#view-guide-level-4")) =~ "STR"
    end

    test "выданное классом здесь есть — в отличие от лестницы конструктора", %{
      conn: conn,
      code: code
    } do
      # Экран просмотра читают целиком, как документацию, и канонический
      # LEVELING GUIDE выданное перечисляет (CLAUDE.md §6). В конструкторе
      # той же строки нет: там колонка показывает решения.
      #
      # ⚠️ Задача 3.147: по умолчанию `○` скрыт — этот тест проверяет, что
      # выдача «есть» (в смысле «умеет отрендериться корректно, когда её
      # смотрят»), а не то, что она видна без единого клика; про сам дефолт
      # свой тест в `build_view_granted_toggle_test.exs`.
      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-guide-level-1-granted-toughness")
      assert render(element(view, "#view-guide-level-1 .pick[data-granted='1']")) =~ "○"
    end

    # Глиф, который надо разгадывать, не работает: человек пришёл по ссылке
    # и не знает, что `○` и `✦` — разные вещи. Плашку «от класса ×N» с карточки
    # конструктора убрали именно за это, так что здесь подпись обязана быть.
    # ⚠️ Легенда осталась одна (у гида) — вторая жила в переписи фитов, которой
    # с 10.08.2026 нет; проверять надо ту, что осталась.
    test "легенда объясняет, что ○ выдан классом, а не выбран", %{conn: conn, code: code} do
      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{code}")

      legend = render(element(view, "#view-guide-legend"))
      assert legend =~ "выдан классом"
      assert legend =~ "фит выбран"
    end

    # ⚠️ Найдено попутно задачей 3.170 (build_view_live.ex): `◆` печатается
    # в строке гида с задачи 3.14 (домены клирика), а в эту легенду не попал
    # никогда — расхождение с `Export.guide_legend/1`, которая называет его
    # с той же задачи. До 3.170 носитель был один — клирик; теперь его
    # несёт каждый волшебник, включая универсалиста.
    test "легенда объясняет ◆ — выбор класса", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      legend = render(element(view, "#view-guide-legend"))
      assert legend =~ "◆"
      assert legend =~ "выбор класса"
    end

    # Задача 3.147: билд, чей гид не несёт вообще ни одной выдачи, не должен
    # показывать контрол, которому нечего переключать — та же осторожность,
    # что у ванильной ветки диалога экспорта (3.146). В реальных билдах это
    # практически недостижимо (все 23 класса обоих ruleset'ов выдают что-то
    # на своём 1-м уровне), поэтому проверяется через `render_assigns/2`
    # с наведённым `has_granted?: false`, а не живым билдом без единого
    # уровня — пустой билд не рендерит секцию гида вовсе (`@character_level
    # > 0`), и тест ничего не доказывал бы про сам гейт.
    test "чекбокса нет, когда гиду нечего показывать", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-granted-checkbox")

      html = render_assigns(view, %{has_granted?: false})
      refute html =~ "view-granted-checkbox"
    end

    # 🔴 Баг 1.14 (Dan 10.08.2026): «если файтер дал фиты какие-то, а потом их же
    # дал DD, то в реальности на момент получения DD эти фиты уже дал файтер и на
    # DD мы просто ничего не получили вместо них, они уже есть». Гид печатал
    # сырую выдачу классового уровня, и на первом уровне второго класса пять
    # строк из шести были шумом ровно там, где игрок ждёт сигнал.
    #
    # ⚠️ ОБЕ половины под одним тестом: «дубль не печатается» зеленеет и на
    # голой разности множеств, которая заодно съедает законные ступени, а
    # «ступень печатается» зеленеет на сыром списке, который и есть баг.
    test "гид печатает прирост владения: дубль ушёл, ступень осталась", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{code}")

      # Уровень 21 — первый уровень Weapon master. Он «выдаёт» `Toughness`,
      # который воин отдал ещё на 1-м, поэтому здесь его больше нет.
      refute has_element?(view, "#view-guide-level-21-granted-toughness")

      # Положительный контроль к `refute`: то, что мастер оружия действительно
      # приносит, на месте, и на 1-м уровне `Toughness` цел — то есть ушёл
      # повтор, а не строка вообще.
      assert has_element?(view, "#view-guide-level-21-granted-ki_damage")
      assert has_element?(view, "#view-guide-level-1-granted-toughness")

      # Вторая половина. `Epic superior weapon focus` мастер оружия выдаёт
      # каждые три классовых уровня под ОДНИМ id (по +1 AB каждый раз), и
      # разность множеств оставила бы только первое из трёх.
      for level <- [33, 36, 39] do
        assert has_element?(
                 view,
                 "#view-guide-level-#{level}-granted-epic_superior_weapon_focus"
               ),
               "уровень #{level}: ступень Epic superior weapon focus пропала из гида"
      end
    end

    test "у выданного видна ступень, а не голое имя семейства", %{conn: conn, code: code} do
      # Weapon master 5 — это 25-й уровень персонажа в этом билде. Одна страница
      # вики на всё семейство ступеней, поэтому ранг едет рядом (CLAUDE.md §9).
      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{code}")

      assert render(element(view, "#view-guide-level-25-granted-superior_weapon_focus")) =~
               "(+1 AB)"

      assert render(element(view, "#view-guide-level-25")) =~ "(+1 AB)"
    end

    test "a known spell is a line of the guide, with its circle in a badge", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Known spells are a decision of the level like a feat, so the guide has to
      # carry them (CLAUDE.md §6).
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:sorcerer],
          spells: %{1 => %{{:circle, 1, 0} => :magic_missile}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      row = render(element(view, "#view-guide-level-1 [data-spell='1']"))

      assert row =~ "Magic missile"
      assert row =~ "circle-badge"
    end
  end

  # Задача 3.94 (Dan 25.08.2026): тот же триггер «что делает фит», что
  # получил конструктор в 3.87 (`BuilderComponents.feat_info/1`) — теперь и
  # в гиде экрана просмотра, на обеих его лестницах, взятой (`row.feats`) и
  # выданной классом (`row.granted`). Это то место, где человек, пришедший по
  # шаренной ссылке и не собиравший этот билд, читает, что вообще делает
  # `Evasion`.
  #
  # ⚠️ `Phoenix.LiveViewTest` не выполняет JS (AGENTS.md): тесты ниже
  # проверяют только то, что рендерит сервер — сам триггер и его `data-*` —
  # никогда не всплывающую панель (её строит хук в браузере). Тот же предел,
  # что уже описан у тестов конструктора (`builder_live_test.exs`, «что делает
  # фит»).
  describe "«что делает фит» в гиде — задача 3.94" do
    test "у взятого слотом фита есть триггер с описанием", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :iron_will}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      pick = element(view, "#view-guide-level-1 .pick", "Iron will")
      html = render(pick)

      assert html =~ "feat-info"
      assert html =~ "will saving throws"
      refute html =~ "[["
    end

    # `Evasion` никогда не берётся слотом (`bonus_for` у него пуст и до, и
    # после Сиалы) — единственный способ увидеть его в билде это выдача
    # классом, а именно она и есть половина 3.94, которую 3.87 не трогала.
    #
    # ⚠️ Триггер ОДИН на всю строку выданного, а не по одному на фит
    # (`#info-view-guide-level-N-granted`, без хвоста с id фита) —
    # `BuilderComponents.feats_info/1`. Это не вкус: попытка поставить
    # триггер на каждое имя измеримо ломает высоту строки на нескольких
    # реальных ширинах (комментарий у `granted_info_entries/1` в
    # `build_view_live.ex`), а хвостовой общий триггер — нет. Данные фита
    # едут JSON-списком в `data-feat-entries`, а не в `data-feat-*` —
    # это форма `feats_info/1`, а не `feat_info/1`.
    test "у фита, выданного классом, тоже есть триггер", %{conn: conn, ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:rogue, 30))

      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#info-view-guide-level-30-granted")

      html = render(element(view, "#info-view-guide-level-30-granted"))
      assert html =~ "data-feat-entries"
      assert html =~ "Quillfire"
      refute html =~ "[["
    end

    # Замер CDP (25.08.2026) нашёл, что триггер на КАЖДОЕ имя реально растит
    # строку на нескольких ширинах — этот тест закрепляет форму, которой
    # правка избежала: у уровня с пятью выдачами (Fighter 1: три яруса брони,
    # щит, Toughness) триггер всё равно ровно один, а не пять.
    test "у строки с несколькими выдачами триггер один, а не по одному на имя", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")

      granted = render(element(view, "#view-guide-level-1 .pick[data-granted='1']"))
      document = LazyHTML.from_fragment(granted)

      assert Enum.count(LazyHTML.query(document, ".feat-info")) == 1

      # Положительный контроль: все пять имён всё равно на месте — сжался
      # триггер, а не список.
      assert granted =~ "Armor proficiency (heavy)"
      assert granted =~ "Armor proficiency (light)"
      assert granted =~ "Armor proficiency (medium)"
      assert granted =~ "Shield proficiency"
      assert granted =~ "Toughness"
    end

    # 🔴 Ровно тот факт, ради которого 3.95 просила эту задачу первой: шард
    # подвинул уровень выдачи (Вор 2 → 30) и добавил свою цитату — печатать
    # ванильное «about the spell school» молча означало бы врать про то,
    # что видит игрок Сиалы.
    test "на siala_41 Evasion помечен «Изменено на Сиале»", %{conn: conn} do
      ruleset = Data.ruleset!("siala_41")
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:rogue, 30))

      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")

      html = render(element(view, "#info-view-guide-level-30-granted"))

      # `data-feat-entries` — JSON внутри HTML-атрибута, поэтому кавычки
      # приезжают как `&quot;`, а не буквальным `"` (иначе атрибут порвал бы
      # сам себя). «Изменён» лежит булем ПОД именем `changed` внутри записи
      # фита, а не как отдельный `data-feat-changed` — та форма у одиночного
      # `feat_info/1`.
      assert html =~ "&quot;changed&quot;:true"
    end

    # Положительный контроль к тесту выше: тот же фит, тот же билд, только
    # ruleset — без него «не помечен на vanilla» ничего бы не доказывал, кроме
    # того, что на siala_41 работает разметка вообще.
    test "на vanilla тот же Evasion НЕ помечен — Сиала его там не трогала", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")

      # Ванильный Rogue отдаёт Evasion на 2-м классовом уровне, не на 30-м.
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:rogue, 2))

      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#info-view-guide-level-2-granted")

      html = render(element(view, "#info-view-guide-level-2-granted"))
      assert html =~ "&quot;changed&quot;:false"
    end

    # 11 сиальских фитов без страницы на Fandom (CLAUDE.md §3) — `description`
    # у них `nil` по контракту `Labels.feat_info/2`, и строка просто не несёт
    # кружка, ровно как в конструкторе (`builder_live_test.exs`, «a Siala-only
    # feat's row offers no info trigger at all»).
    test "у фита без описания (сиальские владения оружием) триггера нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          feats: %{1 => %{general: :siala_blade_proficiency}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      # ⚠️ Не `#view-guide-level-1 .feat-info` целиком: Fighter даром выдаёт
      # `Toughness` на 1-м уровне (CLAUDE.md §3), а у него описание ЕСТЬ —
      # значит своя строка `.pick[data-granted="1"]` кружок несёт, и общий
      # refute по всей строке ловил бы чужой триггер, а не отсутствие
      # своего. Сужаем до конкретного пика по имени, как и другие тесты
      # этого файла («Epic toughness» / «Power attack» выше).
      pick = render(element(view, "#view-guide-level-1 .pick", "Владение клинковым оружием"))

      refute pick =~ "feat-info"
    end
  end

  describe "впустую потраченный слот" do
    # HANDOFF §A.3, решение Дана 02.08.2026: билд, УЖЕ сохранённый со слотом,
    # потраченным на фит, который класс всё равно отдал бы даром позже, не
    # говорил об этом ни словом — ни здесь, ни в конструкторе. Экран
    # просмотра — это как раз то место, куда попадают по чужой ссылке уже
    # с готовым билдом, так что пометка обязана быть видна без единого клика.
    #
    # 🔴 С 10.08.2026 это ЕДИНСТВЕННОЕ место экрана, где подпись есть вовсе:
    # перепись фитов убрана по просьбе Dan, а именно она печатала предложение
    # словами (в гиде стояла пара глифов `✦○` и ссылка на неё). Правило экрана
    # просмотра запрещает глиф, который надо разгадывать (CLAUDE.md §6), так что
    # предложение переехало в гид — и этот тест сторожит, что оно доехало.
    test "фит, который класс отдал бы даром позже, в гиде подписан словами",
         %{conn: conn, ruleset: ruleset} do
      # Тот же билд и тот же факт, что и в тестах конструктора: Ranger 9
      # выдаёт `Improved two-weapon fighting` сам, а этот билд взял его
      # слотом на 1-м уровне — задолго до того, как класс отдал бы его даром.
      build =
        Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:ranger, 9))
        |> Build.put_feat(1, :general, :improved_two_weapon_fighting)

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-guide-level-1 .pick[data-wasted='1']")

      pick = render(element(view, "#view-guide-level-1 .pick[data-wasted='1']"))
      assert pick =~ "Improved two-weapon fighting"
      assert pick =~ "✦"
      assert pick =~ "○"

      # ⚠️ Вот это и есть переехавшая подпись: не «пара глифов», а предложение,
      # называющее класс и уровень. Проверяется на `.v-g-note` строго внутри
      # помеченного `.pick`, а не по тексту всей строки уровня.
      assert has_element?(view, "#view-guide-level-1 .pick[data-wasted='1'] .v-g-note")
      assert pick =~ "Ranger 9"
      assert pick =~ "слот можно освободить"

      assert render(element(view, "#view-guide-legend")) =~ "вышел бы даром"
    end

    # Второй источник того же «даром» — вещь (задача 3.3, правка волны 14
    # 09.08.2026). Человек, пришедший по ссылке, обязан увидеть это без клика
    # так же, как классовую выдачу: `Feats.wasted_text/4` считает оба, и здесь
    # проверяется, что до этого экрана доехал именно второй.
    test "фит, который уже есть с вещи, — та же подпись в гиде",
         %{conn: conn, ruleset: ruleset} do
      # Волшебник: `Toughness` ему не выдаёт ни класс, ни раса, значит пометка
      # может прийти только от объявления.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
          gear: Gear.new(feats: [:toughness])
        )
        |> Build.put_feat(1, :general, :toughness)

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-guide-level-1 .pick[data-wasted='1'] .v-g-note")
      assert render(element(view, "#view-guide-level-1 .pick[data-wasted='1']")) =~ "с вещи"
    end

    # Положительный контроль: у фита, которого никто даром не выдаёт, той же
    # пометки нет — иначе `data-wasted` можно было бы заподозрить в том, что
    # оно просто всегда стоит у взятого фита.
    # ⚠️ Не написано наивно «у уровня 1 референсной фикстуры пометки нет
    # вообще» — это проверялось и оказалось не так: Weapon master (Fighter 20 →
    # Weapon master 21 из общего `setup`) сам выдаёт `Toughness` даром на СВОЁМ
    # 1-м уровне класса (это 21-й персонажа) — Weapon Master в списке восьми
    # классов с бесплатным Toughness на 1-м уровне (CLAUDE.md §3). Значит
    # `Toughness`, взятый слотом на 1-м уровне ЭТОГО билда, впустую
    # по-настоящему. Контроль ведём по `Power attack` с того же уровня — его
    # никакой класс билда не выдаёт — и находку про `Toughness` фиксируем явно,
    # а не тихой заменой фикстуры на более удобную.
    test "у обычного взятого фита подписи нет, а у настоящего впустую — есть", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute has_element?(view, "#view-guide-level-1 .pick[data-wasted='1']", "Power attack")

      # Положительный контроль рядом: сам фит на строке есть, то есть `refute`
      # выше — про отсутствие ПОМЕТКИ, а не про отсутствие фита.
      assert has_element?(view, "#view-guide-level-1 .pick", "Power attack")
      assert has_element?(view, "#view-guide-level-1 .pick[data-wasted='1']", "Toughness")
      assert render(element(view, "#view-guide-legend")) =~ "вышел бы даром"
    end
  end

  describe "AC in equipment" do
    test "stays unknown while nothing has been typed", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert render(element(view, "#view-stat-ac_geared")) =~ "армори"
      assert has_element?(view, "#view-stat-ac_geared[data-unknown='1']")
    end

    test "becomes a number once the build carries gear, with its arithmetic", %{
      conn: conn,
      ruleset: ruleset,
      build: build
    } do
      geared = %{build | gear: Gear.new(ac: %{armor: 8, deflection: 5})}
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(geared)}")

      card = caption_text(render(element(view, "#view-stat-ac_geared")))

      # Задача 3.6: каждый ненулевой тип назван поимённо, а не свёрнут
      # в одно «13 с вещей» — иначе не видно, что 8 дала броня, а 5 —
      # отклонение.
      # ⚠️ Без « + »: разбор с 10.08.2026 — список, слагаемые идут строками
      # (`.v-terms .t`), поэтому проверяется соседство, а не разделитель.
      assert card =~ "база #{ruleset.base_ac} DEX"
      assert card =~ "Броня +8"
      assert card =~ "Отклонение +5"
      refute has_element?(view, "#view-stat-ac_geared[data-unknown='1']")
    end

    # Задача 3.59B: тот же приём, что у AB при Weapon Finesse («от DEX»),
    # заведён и для `Monk AC bonus`. Проверяется отдельно от конструктора —
    # экран просмотра печатает разбор своим списком (`.v-terms`), а не через
    # тот же поп-ап, так что правка обязана быть видна в обоих местах.
    test "Monk AC bonus называет характеристику и на экране просмотра", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:monk, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 18, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      # Голым, а не «в шмоте»: билд не носит вовсе ничего, и карточка «в
      # шмоте» у такого билда — «?» («посчитает армори»), см. describe выше.
      card = caption_text(render(element(view, "#view-stat-ac")))
      assert card =~ "Monk AC bonus (WIS) +4"
    end

    # Постановка 3.55/3.59: монах 5 в кожаном доспехе теряет оба монашеских
    # терма — здесь это тоже обязано быть НАЗВАНО, а не промолчано: билд
    # часто открывают именно этим экраном, по чужой ссылке.
    test "пропавший монашеский терм назван и на экране просмотра, а не молчанием", %{
      conn: conn,
      ruleset: ruleset
    } do
      %Build{} =
        base =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:monk, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 18, cha: 10}
        )

      build = %Build{base | gear: Gear.new(worn: %{armor: :leather})}
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert render(element(view, "#view-stat-ac")) =~ "15"
      assert render(element(view, "#view-stat-ac_geared")) =~ "12"

      card = caption_text(render(element(view, "#view-stat-ac_geared")))
      assert card =~ "Monk AC bonus (WIS) — не работает (надето: Броня) 0"
      assert card =~ "Monk (класс) — не работает (надето: Броня) 0"

      # ⚠️ Положительный контроль: «голым» оба терма живы и ненулевые.
      naked = caption_text(render(element(view, "#view-stat-ac")))
      assert naked =~ "Monk AC bonus (WIS) +4"
      assert naked =~ "Monk (класс) +1"
    end
  end

  describe "honesty" do
    # ⚠️ Задача 3.49 (18.08.2026): было «перенесены не полностью» — заголовок
    # считал решённые споры источников и процитированные константы дырами
    # наравне с настоящими (`BuildCalculatorWeb.Builder.Gaps.tier/1`).
    #
    # 🔴 Задача 3.88 (24.08.2026, решение Dan) — ПЕРЕСМОТР: «и с экрана
    # просмотра и в экспорте прячем тоже». Раньше (задача 3.86, тот же день,
    # что список настоящих дыр опустел) у блока была вторая ветка — при
    # `data_real_count == 0` она печатала «числа не окончательные» вместо
    # молчания. Ветка ушла: баннер про правила Сиалы прячется целиком, пока
    # настоящих дыр нет, но САМ блок (`#view-gaps`) остаётся — список гэпов
    # ЭТОГО билда, которые не гейтятся методологией правил вовсе.
    #
    # ⚠️ Задача 3.148 (31.08.2026): раньше блок держала на экране безусловная
    # строка «числа ниже — база билда, без экипировки» (снята — устарела
    # по факту, вещи в модели есть с 3.3/3.5/3.41/3.132), и вместе с ней
    # `#view-gaps` получил СВОЙ гейт (`data_real_count > 0 or build_count >
    # 0`). Блок остаётся на экране не безусловно, а потому что у фикстуры
    # этого файла (без оружия в руках) есть свой гэп билда — вторая посылка
    # теста ниже, без которой первый `has_element?` зеленел бы вслепую.
    test "the note about missing rules is gone while there is no real data gap, the block stays",
         %{conn: conn, code: code, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      build = Build.new(ruleset_version: ruleset.version)
      summary = Gaps.summary(ruleset, build, Rules.compute(build, ruleset))

      # Положительный контроль на посылку теста (задача 3.86) — см. тот же
      # приём в `builder_live_test.exs`.
      assert summary.data_real_count == 0

      assert has_element?(view, "#view-gaps")
      note = render(element(view, "#view-gaps"))

      refute note =~ "Часть правил Сиалы"
      refute note =~ "ещё не в расчёте"

      # Вторая посылка (задача 3.148): блок остался не сам по себе, а из-за
      # списка гэпов ЭТОГО билда — без этого `has_element?` выше доказывал
      # бы только то, что `#view-gaps` не сломан, а не то, ЧТО его держит.
      assert has_element?(view, "#view-gaps-list")
      assert note =~ "не смогло посчитать"
    end

    # ⚠️ Главный тест ворот, который требует постановка задачи: на
    # СИНТЕТИЧЕСКОМ ruleset'е с наведённой дырой, не на живых данных —
    # живые сегодня дают ноль, и тест на них молча перестал бы что-либо
    # проверять, если бы условие сломалось в положение «всегда закрыто».
    test "the note returns on its own once a real data gap exists", %{
      conn: conn,
      code: code,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      synthetic_ruleset = %{ruleset | gaps: [induced | ruleset.gaps]}
      build = Build.new(ruleset_version: ruleset.version)

      synthetic_gaps =
        Gaps.summary(synthetic_ruleset, build, Rules.compute(build, synthetic_ruleset))

      assert synthetic_gaps.data_real_count > 0

      html = render_assigns(view, %{gaps: synthetic_gaps})

      assert html =~
               "Часть правил Сиалы ещё не в расчёте — #{synthetic_gaps.data_real_count} пробелов в данных."

      assert html =~
               "Среди них — заклинания, кастомные системы шарда и часть классовых изменений."
    end

    test "this build's own gaps are spelled out, not just counted", %{
      conn: conn,
      code: code,
      build: build,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # Раньше тест держался на Power Attack: его требования считались
      # непрочитанными, и экран называл его поимённо. Сегодня `strength 13+`
      # разобран и проверяется, так что этот пробел исчез — правильно, а не
      # потерялся. Суть проверки не в конкретном фите, а в том, что пробелы
      # билда перечислены **словами**, а не свёрнуты в счётчик: человек,
      # пришедший по ссылке, по умолчанию поверит числам.
      #
      # ⚠️ «не применено» (родовая фраза `{:class_change, …}`-гэпов, Labels
      # `class_change_reason/3`) стояло здесь как маркер именно потому, что
      # у этого билда (Fighter 20 / Weapon Master 21) висел
      # `weapon_master / attack_bonus_progression` — 17.08.2026 (задача про
      # Мастера оружия) он снят замером, и «не применено» у этого билда
      # больше НИКОГДА не встречается: у обоих его классов не осталось
      # ни одного `class_change`-гэпа с нашим получателем (fighter не нёс
      # его никогда, у weapon_master осталась только незадетая правкой
      # оговорка про качество «in a melee weapon», рендерится иначе).
      # ⚠️ Маркер менялся дважды. Сперва «не применено», потом «не считаем» —
      # и вторая фраза продержалась до 25.08.2026: задача 3.95 сняла оговорки
      # об условных прибавках решением владельца, и вместе с ними у этого
      # билда исчезли `Hardiness vs. poisons`, `Battle training` и семь их
      # соседей, то есть все строки, где эта фраза стояла.
      #
      # ⚠️ Маркер менялся ТРЕТИЙ раз — 25.08.2026, задача 3.100 сняла оговорку
      # про выгоды Сагры (у этого билда все классы из группы), и вместе с ней
      # ушла строка «Воины Сагры». Три правки подряд по одной и той же причине,
      # и вывод из них общий: **список маркеров-фраз стареет быстрее, чем
      # утверждение теста**, потому что каждая фраза — это чей-то гэп, а гэпы
      # для того и заводятся, чтобы однажды закрыться.
      #
      # 🔴 Поэтому маркеров больше нет вовсе. Утверждение — «пробелы ЭТОГО
      # билда перечислены словами» — теперь проверяется против самого билда:
      # берём его гэпы у ядра, просим у веб-слоя подпись каждого и требуем
      # найти её на экране. Такой тест не может протухнуть от правки данных:
      # изменится набор гэпов — изменятся и ожидаемые фразы. И он строже
      # прежнего: раньше проверялись три строки из десяти, теперь все.
      list = render(element(view, "#view-gaps-list"))
      stats = Rules.compute(build, ruleset)

      assert has_element?(view, "#view-gaps-list")

      # ⚠️ Положительный контроль: пустой список гэпов сделал бы цикл ниже
      # пустым, и тест зеленел бы, ничего не проверяя.
      assert stats.gaps != []

      for gap <- stats.gaps do
        # ⚠️ Первые 40 символов, а не вся подпись: HEEx переносит длинные
        # строки и подставляет сущности, а начало фразы у каждой подписи своё
        # и никогда не совпадает у двух разных гэпов.
        phrase = gap |> Labels.gap(ruleset) |> String.slice(0, 40)

        assert list =~ phrase, "гэп #{inspect(gap)} не назван на экране словами"
      end
    end

    # Раньше здесь безусловно висело «фиты, которые класс выдаёт сам, в данных
    # не размечены». Это больше не правда: `granted_feats` лежат в
    # `priv/rules/*/classes.json`, и неверный пробел хуже отсутствующего — он
    # приучает не читать список, который существует ровно чтобы его читали.
    test "the blanket gap about class-granted feats is gone", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute render(element(view, "#view-gaps-list")) =~ "не размечены"
    end

    # 🔴 Задача 3.148 (31.08.2026, Dan): «the note points at the sources page»
    # проверяло `#view-sources-link` — второй вход на `/sources`, дубль
    # `#footer-sources-link`. Снят целиком (Dan: «предупреждение убрать»),
    # атрибуция при этом не пострадала — `site_footer_test.exs`'s «экран
    # просмотра по коду» уже держит `#footer-sources-link` именно на этом
    # маршруте (`/b/:code`), той же фикстурой `build_code/0`. Этот тест не
    # переписан, а заменён отрицательным контролем: дубля больше нет вовсе,
    # и это часть того же самого решения, а не отдельный факт.
    test "there is no second sources link duplicating the footer's", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute has_element?(view, "#view-sources-link")
      refute has_element?(view, "#view-gaps-sources")

      # Положительный контроль: атрибуция сама никуда не делась — просто
      # не задваивается. `has_element?` тут дешёвая подстраховка, полное
      # покрытие футера (ссылка + текст лицензии) — `site_footer_test.exs`.
      assert has_element?(view, "#site-footer #footer-sources-link")
    end
  end

  # Задача 3.148 (31.08.2026, Dan): «предупреждение убрать, вместо него
  # рекомендацию экипировать персонажа». Гейт — `Gear.any?/1`, а не версия
  # ruleset'а и не гэпы: билд ничего не сказал про вещи, а не «числа
  # неполные» (та мысль осталась у `#view-gaps` выше, только теперь честно
  # гейтится своими причинами, а не безусловной строкой).
  describe "рекомендация экипировать билд (задача 3.148)" do
    test "билд без единой вещи показывает рекомендацию с рабочей ссылкой", %{
      conn: conn,
      code: code
    } do
      # Фикстура файла `gear` не несёт вовсе — положительный контроль на это
      # ниже, иначе `assert has_element?` мог зеленеть и на сломанном гейте.
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-gear-hint")
      hint = render(element(view, "#view-gear-hint"))
      assert hint =~ "AC"
      assert hint =~ "AB"

      {:ok, builder, _html} =
        view |> element("#view-gear-hint-link") |> render_click() |> follow_redirect(conn)

      # Та же ссылка, что у «Открыть в конструкторе»: `~p"/?b=#{@code}"`
      # открывает ЭТОТ ЖЕ билд, а не пустой конструктор.
      assert has_element?(builder, "#split-fighter")
    end

    test "билд с любой вещью — рекомендации нет", %{conn: conn, build: %Build{} = build} do
      # ⚠️ Не armor, не AC, не сейв — оружия в одной руке достаточно
      # (`Gear.any?/1`'s own moduledoc: и оружие, и надетое, и число — три
      # независимых повода считать, что игрок хоть что-то сказал про вещи).
      code = Encoding.encode(%Build{build | gear: Gear.new(weapon: :katana)})
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      refute has_element?(view, "#view-gear-hint")
    end
  end

  describe "the way out" do
    test "the same build opens in the constructor", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      {:ok, builder, _html} =
        view |> element("#open-in-builder") |> render_click() |> follow_redirect(conn)

      assert has_element?(builder, "#split-fighter")
      assert render(element(builder, "#character-level")) =~ "41"
    end

    test "the canonical text is available to read and to copy", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#copy-text")
      view |> element("#show-text") |> render_click()

      text = render(element(view, "#view-export-text"))
      assert text =~ "LEVELING GUIDE"

      # ⚠️ Не «SKILL GUIDE» отдельным блоком — задача 3.145 слила его в
      # строку уровня для `siala_41` (умолчание этого экрана). Число
      # рангов остаётся видимым, просто на той же строке, что и фит.
      assert text =~ "Discipline +4 (4)"
    end
  end

  describe "round trip between the two screens" do
    test "the constructor's share link points at the view screen", %{conn: conn} do
      {:ok, builder, _html} = live(conn, ~p"/")

      builder |> element("#level-1") |> render_click()
      builder |> element("#class-card-fighter") |> render_click()

      assert has_element?(builder, "#mode-view")
      assert render(element(builder, "#share")) =~ "/b/#{Encoding.current_version()}."
    end
  end

  describe "правка раннего уровня перепроверяет поздние — экран просмотра (задача 1.3)" do
    # Тот же билд, что уже проверен ядром (`illegal_levels_test.exs`) и
    # конструктором (`builder_live_test.exs`): Fighter 1–9 набирает все шесть
    # фитов, которые требует Weapon Master (`dodge`, `mobility`, `expertise`,
    # `spring_attack`, `weapon_focus`, `whirlwind_attack`) плюс Intimidate 4,
    # дальше три уровня самого класса — билд легален целиком, ни одна из
    # шести не лишняя. Билд, открытый по ссылке (а не собранный по шагам
    # в конструкторе), ни разу не проходил через `validate_level_up/3` —
    # это и есть сценарий, на котором ложная легальность возможна вообще.
    defp weapon_master_view_build(ruleset) do
      Build.new(
        ruleset_version: ruleset.version,
        levels: List.duplicate(:fighter, 9) ++ List.duplicate(:weapon_master, 3),
        base_abilities: %{str: 14, dex: 14, con: 12, int: 14, wis: 10, cha: 8},
        skills: %{1 => %{intimidate: 4}},
        feats: %{
          1 => %{:general => :dodge, {:class_bonus, :fighter} => :weapon_focus},
          2 => %{{:class_bonus, :fighter} => :mobility},
          3 => %{:general => :expertise},
          4 => %{{:class_bonus, :fighter} => :spring_attack},
          6 => %{:general => :whirlwind_attack}
        }
      )
    end

    # Положительный контроль — обязателен рядом с «билд нарушает правила»
    # ниже (AGENT_QUEUE, «пустые проверки»): без него любой из тестов внизу
    # мог бы зеленеть и в мире, где отметка стоит на каждом уровне подряд.
    test "легальный билд не получает ни одной пометки — ни в сводке, ни в гиде", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = weapon_master_view_build(ruleset)
      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      refute has_element?(view, "#view-illegal")

      for level <- 1..12 do
        refute has_element?(view, "#view-guide-level-#{level}[data-illegal='1']")
        refute has_element?(view, "#view-guide-level-#{level}-issue")
      end
    end

    test "снятие фита, который держал уровни Weapon Master, названо поимённо — в сводке и в гиде",
         %{conn: conn, ruleset: ruleset} do
      %Build{} = build = weapon_master_view_build(ruleset)
      without_weapon_focus = %Build{build | feats: %{build.feats | 1 => %{general: :dodge}}}

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(without_weapon_focus)}")

      assert has_element?(view, "#view-illegal")
      assert render(element(view, "#view-illegal")) =~ "3 уровня с нарушением правил"

      for level <- [10, 11, 12] do
        assert has_element?(view, "#view-illegal-#{level}")
        summary_row = render(element(view, "#view-illegal-#{level}"))
        assert summary_row =~ "Weapon master"
        assert summary_row =~ "Weapon focus"

        # Гид — то самое место, куда смотрят, чтобы понять, ГДЕ чинить:
        # отметка обязана сидеть на КОНКРЕТНОМ уровне, а не только в сводке.
        assert has_element?(view, "#view-guide-level-#{level}[data-illegal='1']")
        guide_row = render(element(view, "#view-guide-level-#{level}-issue"))
        assert guide_row =~ "Weapon master"
        assert guide_row =~ "Weapon focus"
      end

      # Снятый фит сам по себе не отмечает свой собственный уровень — только
      # то, что от него зависело (тот же инвариант, что в ядре и в
      # конструкторе, `illegal_levels_test.exs`).
      refute has_element?(view, "#view-illegal-1")
      refute has_element?(view, "#view-guide-level-1[data-illegal='1']")
    end

    # Находка, а не выдумка (проверено запуском, не угадано): фикстура этого
    # файла (`setup` вверху, Fighter 20 → Weapon master 21) была нелегальна
    # с самого начала — её 21 уровню Weapon Master не хватает всех шести
    # фитов и Intimidate 4, просто до сих пор это было негде увидеть, потому
    # что экран просмотра лестницу не проверял вовсе. Тест зафиксирован
    # намеренно: если фикстуру когда-нибудь исправят (добавят нужные фиты),
    # он обязан упасть и потребовать правки, а не молчать.
    test "фикстура этого файла (Fighter 20 → Weapon master 21) сама оказалась нелегальной", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-illegal")
      assert has_element?(view, "#view-guide-level-21[data-illegal='1']")
      assert render(element(view, "#view-guide-level-21-issue")) =~ "Weapon master"
    end
  end

  describe "домены клирика в гиде (задача 3.14)" do
    test "выбранные домены названы на СВОЁМ уровне класса, не на первом уровне персонажа", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          # Клирик пятым классом, после четырёх уровней воина — «первый
          # уровень клирика» это уровень 5 персонажа, не 1-й.
          levels: List.duplicate(:fighter, 4) ++ List.duplicate(:cleric, 3),
          class_choices: %{cleric: [:air, :war]},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-guide-level-5-domains")
      text = render(element(view, "#view-guide-level-5-domains"))
      assert text =~ "Air"
      assert text =~ "War"

      # Не на 6-м и 7-м (2-й и 3-й уровень клирика) — выбор один на весь билд.
      refute has_element?(view, "#view-guide-level-6-domains")
      refute has_element?(view, "#view-guide-level-7-domains")
      # И не на 1-м — там ещё воин, а не клирик.
      refute has_element?(view, "#view-guide-level-1-domains")
    end

    # Положительный контроль: билд без клирика вовсе не несёт ни одной
    # пометки о доменах — иначе тест выше зеленел бы и у реализации,
    # которая печатает эту строку всем подряд.
    test "билд без клирика не показывает доменов вовсе", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 3),
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      for level <- 1..3 do
        refute has_element?(view, "#view-guide-level-#{level}-domains")
      end
    end

    # Домены не выбраны (старая ссылка или незакрытый билд) — гид молчит,
    # а не пишет пустое «:». `guide_increase/3` уже устроен так же для
    # прибавки к стату; гид документирует то, что состоялось.
    test "домены не выбраны — строка в гиде не появляется", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:cleric],
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      refute has_element?(view, "#view-guide-level-1-domains")
    end
  end

  describe "школа волшебника в гиде и итогах (задача 3.10)" do
    test "выбранная школа названа на СВОЁМ уровне класса, не на первом уровне персонажа", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 4) ++ List.duplicate(:wizard, 3),
          class_choices: %{wizard: [:evocation]},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-guide-level-5-domains")
      text = render(element(view, "#view-guide-level-5-domains"))
      assert text =~ "Evocation"

      # Не на 6-м и 7-м (2-й и 3-й уровень волшебника) — выбор один на весь
      # билд, а не на уровень.
      refute has_element?(view, "#view-guide-level-6-domains")
      refute has_element?(view, "#view-guide-level-7-domains")
      refute has_element?(view, "#view-guide-level-1-domains")
    end

    # ⚠️ Главное отличие от доменов клирика (у которого «не выбраны» скорее
    # означает незакрытый или сломанный билд): волшебник-универсал —
    # ЛЕГАЛЬНЫЙ финал, и это не помечено как проблема лестницы («задача 1.3»
    # отмечает только настоящие нарушения требований).
    #
    # ⚠️ Задача 3.170: здесь стояло «гид молчит про школу» — устарело.
    # Универсал не имеет своего значения в билде («ничего не выбрано» и есть
    # универсалист), но игрок в игре видит это состояние НАЗВАННЫМ (`General`,
    # скриншот Dan 02.09.2026), и гид теперь называет его тем же словом —
    # иначе читатель чужой ссылки не отличит университета от незакрытого
    # билда.
    test "волшебник-универсал: гид называет школу General, а лестница не помечает уровень", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:wizard],
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-guide-level-1-domains")
      text = render(element(view, "#view-guide-level-1-domains"))
      assert text =~ "General"

      refute has_element?(view, "#view-guide-level-1[data-illegal='1']")
    end
  end
end
