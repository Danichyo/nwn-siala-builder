defmodule BuildCalculatorWeb.SourcesLiveTest do
  @moduledoc """
  The `/sources` page's own content — mostly the CC BY-SA attribution
  (`site_footer_test.exs` already proves the page is reachable from every
  route), plus, since task 3.88 (24.08.2026), the methodology section that
  moved here off the build screens.

  Dan, looking at a 17-entry gaps panel that was mostly RESOLVED records
  after task 3.86 closed the last real one: "данную секцию с сайта уже
  убрал бы… для пользователей я предлагаю дыры больше не показывать";
  "прячем до момента появления дыр, в sources можно оставить". The build
  screens gate their data-gap sections on `data_real_count > 0`
  (`BuilderLiveTest`, `BuildViewLiveTest`); this page prints the resolved
  and accepted-constant lists **unconditionally and in full**, because
  answering "откуда правила" does not depend on whether a real hole
  happens to exist today.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Gaps

  test "the page renders on its own", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sources")

    assert has_element?(view, "#sources-page")
  end

  describe "методология — задача 3.88" do
    # Сегодняшний ruleset несёт 0 реальных дыр, 8 решённых расхождений и
    # 8 принятых допущений (`gaps_test.exs`, «today's siala_41 split is
    # 0 real / 8 resolved / 8 assumed») — то есть оба раздела ниже видны
    # живыми данными без единого синтетического вмешательства.
    test "решённые расхождения источников видны, и в них есть пример из задачи", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")

      assert has_element?(view, "#sources-gaps-resolved")
      resolved = render(element(view, "#sources-gaps-resolved"))

      assert resolved =~ "Источники спорят"

      # Тот самый пример, который задача 3.88 цитирует как «ответ на вопрос
      # «откуда правила»» — если он однажды закроется по-настоящему, это не
      # повод удалить проверку, а сигнал завести новый живой пример.
      assert resolved =~ "Pick pocket"
      assert resolved =~ "Harper scout"
    end

    test "принятые допущения и константы видны, с цитатой источника", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")

      assert has_element?(view, "#sources-gaps-assumed")
      assumed = render(element(view, "#sources-gaps-assumed"))

      assert assumed =~ "Допущения"
      assert assumed =~ "fandom:Armor class"
    end

    # Списки НЕ сэмплированы (в отличие от панели конструктора, которая
    # режет каждый вид до трёх строк): «Источники спорят» (8) + «Выведено,
    # не прочитано» (1) — обе группы внутри «resolved» — дают 9 строк
    # разом, не 3 + 3 = 6, как показала бы сэмплированная выборка.
    # ⚠️ 7 → 8 спорящих 25.08.2026 (задача 3.104): к шести классовым навыкам
    # прибавился спор лейбла и категории Fandom о том, требует ли Исполнение
    # тренировки. Разница между сэмплом и полным списком от этого только
    # заметнее — панель по-прежнему покажет три.
    test "список не урезан до примера — обе группы «resolved» несут все свои записи", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/sources")

      resolved = render(element(view, "#sources-gaps-resolved"))
      matches = Regex.scan(~r/<li>/, resolved)

      assert length(matches) == 9
    end

    # ⚠️ `SourcesLive.moduledoc` — вики Сиалы на этой странице не называется
    # никогда (Dan, 04.08.2026: у неё нет своей лицензии, вопрос кредита —
    # отдельный разговор), и `SiteFooterTest`, «вики Сиалы не упомянута
    # нигде на странице», это проверяет для страницы целиком. Один из
    # `@assumed_kinds` называет её по имени сам, дословно
    # («class_unavailable_feats_vanilla»: «the Siala wiki is silent about
    # this») — эта запись обязана быть исключена ИМЕННО из вывода на эту
    # страницу, а не пропасть из данных: `gaps_test.exs`
    # («today's siala_41 split is… 8 assumed») по-прежнему видит её.
    test "принятые допущения не называют вики Сиалы по имени", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")

      assumed = render(element(view, "#sources-gaps-assumed"))
      refute assumed =~ "вики Сиалы"
    end

    # Положительный контроль (иначе «блок пуст» и «блок правильно пуст»
    # неотличимы): раздел настоящих дыр не рисуется, пока их 0.
    test "раздела настоящих дыр нет, пока в ruleset'е ноль реальных дыр", %{conn: conn} do
      ruleset = Data.ruleset!()
      assert Gaps.data_tiers(ruleset).real == []

      {:ok, view, _html} = live(conn, ~p"/sources")

      refute has_element?(view, "#sources-gaps-real")
    end

    # ⚠️ Главный тест ворот в эту сторону — на СИНТЕТИЧЕСКОМ ruleset'е
    # с наведённой дырой, не на живых данных (живые сегодня дают ноль).
    # Rulesets are compiled in (`BuildCalculator.Data`, "compiled into the
    # beam") — a real mount cannot pick up an ad-hoc ruleset by version
    # string, so this renders the LiveView's own template directly with
    # one assign overridden. `assigns` comes from an actually mounted,
    # working page (`:sys.get_state/1` — sanctioned for LiveView test
    # synchronisation by `AGENTS.md`, used here to read state instead),
    # so every assign other than `:gap_tiers` stays genuine.
    test "раздел настоящих дыр появляется сам, если в данных наводится настоящая дыра", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/sources")
      %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)

      ruleset = Data.ruleset!()
      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      synthetic_ruleset = %{ruleset | gaps: [induced | ruleset.gaps]}

      html =
        assigns
        |> Map.put(:gap_tiers, Gaps.data_tiers(synthetic_ruleset))
        |> BuildCalculatorWeb.SourcesLive.render()
        |> rendered_to_string()

      assert html =~ ~s(id="sources-gaps-real")
      assert html =~ "Toughness"
    end
  end
end
