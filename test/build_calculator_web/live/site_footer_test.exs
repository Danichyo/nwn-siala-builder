defmodule BuildCalculatorWeb.SiteFooterTest do
  @moduledoc """
  CC BY-SA attribution: the footer (`BuildCalculatorWeb.Layouts.site_footer/1`)
  and the dedicated `/sources` page it points to.

  `Layouts.app/1` renders the footer once, so *in principle* one hit proves
  it works everywhere — but the task this closes was explicitly to check that
  by the router's list of routes, not by two picked at random (a page that
  builds its own header instead of `Layouts.site_header` could plausibly have
  skipped `Layouts.app` too). So every routed LiveView action gets its own
  assertion below, split by whether it is reachable signed out.
  """
  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.GapReceivers
  alias BuildCalculatorWeb.Builder.Labels

  describe "футер виден без аккаунта" do
    test "конструктор", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_footer(view)
    end

    test "экран просмотра по коду", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/b/#{build_code()}")
      assert_footer(view)
    end

    test "экран просмотра сохранённого публичного билда", %{conn: conn} do
      build = build_fixture(user_scope_fixture(), %{visibility: :public})
      {:ok, view, _html} = live(conn, ~p"/builds/#{build}")
      assert_footer(view)
    end

    test "публичная лента", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library")
      assert_footer(view)
    end

    test "регистрация", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/register")
      assert_footer(view)
    end

    test "вход", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log-in")
      assert_footer(view)
    end

    test "подтверждение по ссылке из письма", %{conn: conn} do
      user = unconfirmed_user_fixture()
      {token, _} = generate_user_magic_link_token(user)

      {:ok, view, _html} = live(conn, ~p"/users/log-in/#{token}")
      assert_footer(view)
    end

    test "страница «Источники» сама", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      assert_footer(view)
    end
  end

  describe "футер виден вошедшему пользователю" do
    setup :register_and_log_in_user

    test "мои билды", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/library/mine")
      assert_footer(view)
    end

    test "лента группы", %{conn: conn, scope: scope} do
      group = group_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/library/group/#{group}")
      assert_footer(view)
    end

    test "список групп", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/groups")
      assert_footer(view)
    end

    test "страница одной группы", %{conn: conn, scope: scope} do
      group = group_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/groups/#{group}")
      assert_footer(view)
    end

    test "настройки аккаунта", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings")
      assert_footer(view)
    end

    test "форма сохранения нового билда", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/builds/new?b=#{build_code()}")
      assert_footer(view)
    end

    test "форма правки сохранённого билда", %{conn: conn, scope: scope} do
      build = build_fixture(scope)
      {:ok, view, _html} = live(conn, ~p"/builds/#{build}/edit")
      assert_footer(view)
    end
  end

  describe "текст футера" do
    test "называет источник, лицензию, факт переработки и ссылку на подробности", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      footer = render(element(view, "#site-footer"))

      assert footer =~ "NWN Wiki (Fandom)"
      assert footer =~ "CC BY-SA 3.0"
      assert footer =~ "переработанных"

      assert has_element?(
               view,
               ~s(a#footer-fandom-link[href="https://nwn.fandom.com/"])
             )

      assert has_element?(
               view,
               ~s(a#footer-license-link[href="https://creativecommons.org/licenses/by-sa/3.0/"])
             )
    end

    test "рядом стоит оговорка о неаффилированности", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      footer = render(element(view, "#site-footer"))

      assert footer =~ "не связан"
      assert footer =~ "BioWare"
      assert footer =~ "Beamdog"
      assert footer =~ "Wizards of the Coast"
      assert footer =~ "администрацией шарда"
    end

    # ⚠️ Решение Dan 04.08.2026: вики Сиалы в атрибуции не упоминается вовсе —
    # у неё нет своей лицензии, и признание её как источника отложено на
    # отдельный разговор. Эта задача закрывает только обязательство Fandom.
    test "вики Сиалы не упомянута", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      footer = render(element(view, "#site-footer"))

      refute footer =~ "wiki.siala"
      refute footer =~ "siala.kiev.ua"
      refute footer =~ "вики Сиалы"
      refute footer =~ "вики шарда"
    end

    test "ссылка ведёт на страницу «Источники»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, sources, _html} =
        view |> element("#footer-sources-link") |> render_click() |> follow_redirect(conn)

      assert has_element?(sources, "#sources-page")
    end
  end

  describe "страница «Источники»" do
    test "открывается без аккаунта по прямой ссылке", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      assert has_element?(view, "#sources-page")
    end

    test "называет источник и лицензию с рабочими ссылками", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")

      assert has_element?(
               view,
               ~s(a#sources-fandom-link[href="https://nwn.fandom.com/"])
             )

      assert has_element?(
               view,
               ~s(a#sources-license-link[href="https://creativecommons.org/licenses/by-sa/3.0/"])
             )

      assert has_element?(
               view,
               ~s(a#sources-legalcode-link[href="https://creativecommons.org/licenses/by-sa/3.0/legalcode"])
             )

      page = render(view)
      assert page =~ "Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)"
    end

    test "описывает реальный объём заимствования, а не «пара цитат»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      page = render(view)

      # Числа должны совпадать с priv/rules/vanilla/*.json — если кто-то
      # честно обновит данные, не тронув эту страницу, тест это заметит.
      assert page =~ "23 класс"
      assert page =~ "299 фитов"
      assert page =~ "7 рас"
      assert page =~ "28 навыков"
      assert page =~ "303 заклинания"

      assert page =~ "BAB" or page =~ "базовая атака"
      assert page =~ "спас"
    end

    # Задача 3.28: постоянное место для фактов шарда, которые перестали
    # считаться пробелами в конструкторе. ⚠️ Числа обязаны быть посчитанными:
    # вписанное руками «126» и есть та самая непроверяемая строка, из-за которой
    # заголовок конструктора полгода называл цифру, никем не пересчитанную.
    test "называет факты шарда числами, посчитанными из данных", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      census = GapReceivers.census(Data.ruleset!()).classes
      shard = render(element(view, "#sources-shard-facts"))

      assert has_element?(view, "#sources-shard-heading")
      assert shard =~ "прочитано #{census.total}"
      assert shard =~ "В расчёт идут #{census.ours}"
      assert shard =~ "#{census.applied} уже применены"
      assert shard =~ "#{census.gaps} пока нет"

      # Положительный контроль к «посчитано»: сегодня это 124 / 48 / 38 / 10,
      # и если данные поменяются, упадёт снапшот ниже, а не эта проверка.
      # ⚠️ Стояло 126 / 56 / 37 / 19 — сдвинуто 10.08.2026 правкой данных
      # (решение Dan: `Rage`, `Bull's strength` и `Shadow Evade` — баффы),
      # ещё раз 13.08.2026 замером L1 («Свет плута» и Набор для обезвреживания
      # ловушек — используемые предметы, в значение навыка не идут), и
      # 17.08.2026 ответом Dan по Тайному лучнику: две записи сняты, третья
      # применена, отсюда сразу и `total` вниз, и `applied` вверх.
      # Канарейка отработала все три раза: четыре проверки выше зеленели, потому
      # что берут числа из `census`, а падала ровно эта строка.
      # ⚠️ 48 / 10 → 47 / 9 (17.08.2026, решение Dan «если штрафы вору идут
      # только в режиме хайда, то мы их не показываем»): у штрафа вора в режиме
      # скрытности переставлен получатель. `total` и `applied` не двинулись —
      # запись на месте и по-прежнему не применена, — и это тот самый случай,
      # ради которого здесь стоят все четыре числа, а не одно: правка обязана
      # быть видна как переклассификация, а не как потерянный факт.
      # ⚠️ 124 / 47 / 9 → 123 / 45 / 7 (17.08.2026, задача про Мастера оружия):
      # обе записи ВМ слиты в одну и переставлены на `counted_elsewhere` —
      # `total` падает вместе с `ours` и `gaps` (все три несла та же запись),
      # `applied` не тронут: ни старые записи, ни новая не были применены.
      # ⚠️ 38 / 7 → 39 / 6 (21.08.2026, задача 3.72): у Тайного лучника посчитаны
      # дополнительные атаки. `total` и `ours` не двинулись — запись на месте
      # и получатель у неё прежний (`attacks_per_round`, наш), — а `applied`
      # и `gaps` разошлись в разные стороны на одну и ту же единицу. Это третья
      # форма правки в этом списке: не переклассификация (штраф вора), не
      # слияние записей (Мастер оружия), а **факт, который модель научилась
      # считать**.
      # ⚠️ 39 / 6 → 41 / 4 (21.08.2026, задача 3.73): та же, третья форма —
      # `bonus_feat_pool` Священника и Друида модель научилась считать.
      # `total` и `ours` снова не двинулись (получатель прежний,
      # `feat_availability`, наш), `applied` и `gaps` снова разошлись на одно
      # и то же число. ⚠️ На ДВА, а не на четыре: две записи той же формы
      # (Чемпион Торма, Рейнджер) остались гэпами — источник не называет
      # у них ни уровней, ни состава.
      # ⚠️ 41 / 2 → 43 / **0** (24.08.2026, задача 3.85): та же третья форма
      # в четвёртый раз, применены и оставшиеся две записи `bonus_feat_pool`.
      # `total` и `ours` снова не двинулись, `applied` и `gaps` снова разошлись
      # на одно и то же число. 🔴 Повод при этом НЕ «источник назвал числа»
      # (у Чемпиона Торма он их так и не назвал), а ЗАМЕР Dan 24.08.2026
      # (GAME_CHECKS.md, U1 и U2) — и он же показал, что гэп был ложным:
      # пул наполняется со страниц самих фитов и был верен всё это время.
      # 🔴 `gaps == 0` означает, что страница «Источники» печатает «0 пока нет»
      # — это состояние, а не поломка: `reported?` у слоя классов по-прежнему
      # `true`, дорога до `ruleset.gaps` открыта.
      # ⚠️ 123 / 43 / 43 → 124 / 44 / 44 (25.08.2026, задача 3.96): Пурпурный
      # рыцарь дракон получил факт `progression_table` (полная таблица БАБ
      # и сейвов, применена сразу, получатели `bab`/`attacks_per_round`/
      # `saving_throws`) — `total`, `ours` и `applied` растут вместе на
      # единицу, `gaps` не движется, потому что новая запись не была
      # неприменённой ни на миг.
      # ⚠️ 44 / 44 → 45 / 45 (25.08.2026, задача 3.101): факт Тайного лучника
      # про арбалеты («Все классовые умения теперь распространяются на малый
      # и большие арбалеты») применён и одновременно ПОЛУЧИЛ нашего получателя.
      # Пятая форма правки в этом списке: не переклассификация, не слияние,
      # не «модель научилась считать» и не «данные пополнились», а **соседнее
      # правило доехало до ответа** — до 3.101 умение, в которое падает факт
      # (`Enchant arrow`), само стояло `not_modelled`, и получателя
      # `attack_bonus` у факта не было потому, что нашего числа он не двигал.
      # `total` и `gaps` при этом не тронуты.
      # ⚠️ 124 / 45 / 45 → 134 / 55 / 55 (27.08.2026, задача 3.129): десять
      # новых фактов, `source.kind: "hak"` — сверка с таблицами движка, не
      # вики (см. docs/hak_diff_classes.md). Все десять ПРИМЕНЕНЫ сразу
      # (легли на уже существующие клаузы `apply_change`) и все несут наш
      # получатель, поэтому `total`, `ours` и `applied` растут вместе на
      # десять, а `gaps` не движется — шестая форма правки в этом списке,
      # но арифметически та же, что у 3.96: новые записи, не переезды.
      # ⚠️ 134 / 55 / 55 → 135 / 56 / 56 (02.09.2026, задача 3.168): один факт,
      # `bonus_feat_pool` Паладина — сиальские владения оружием в его эпическом
      # бонусном слоте. Источник — ЗАМЕР (`GAME_CHECKS.md`, AK1), а не страница:
      # паладина не называет ни страница класса, ни страницы самих владений.
      # Арифметика та же, что у 3.96 и 3.129: применён сразу, получатель наш,
      # `gaps` не движется.
      assert {census.total, census.ours, census.applied, census.gaps} == {135, 56, 56, 0}
    end

    # ⚠️ Слой фитов, 14.08.2026. Абзац отдельный, а не приписка к абзацу
    # классов, и числа не сложены: 126 фактов о классах — прочитанная человеком
    # проза, 201 о фитах — в основном четыре жирных лейбла со страницы, и
    # «прочитано 327» отвечало бы на вопрос, которого никто не задавал.
    #
    # ⚠️ `ours` у фитов страница НЕ печатает, и это проверяется отдельно ниже:
    # разметку там получили только неприменённые факты плюс две применённые
    # (`Improved evasion`, `artist`), поэтому 174 — это в основном «без метки»,
    # а не классификация.
    test "фиты названы своим абзацем и своими числами", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      census = GapReceivers.census(Data.ruleset!()).feats
      feats = render(element(view, "#sources-shard-feats"))

      assert feats =~ "прочитано #{census.total}"
      assert feats =~ "Применены #{census.applied}"
      assert feats =~ "Остальные #{census.unapplied}"
      assert feats =~ "из них #{census.gaps} — про то, что калькулятор показывает"

      # Снимок: 198 / 177 / 21 / 0 — упадёт первым, если данные поедут.
      # ⚠️ Было 196 / 175; выросло 16.08.2026 на две ПРИМЕНЁННЫЕ записи (замер
      # H9 двинул ветки монаха и ШД у `Improved evasion`). Неприменённых
      # и гэпов не прибавилось — это и отличает пополнение данных от новой дыры.
      # ⚠️ `gaps` 1 → 0 (17.08.2026, решение Dan): тот же `Improved evasion`
      # перестал быть гэпом — замер H9 закрыл остаток, ради которого оговорка
      # держалась. Страница честно печатает ноль, а не прячет строку: «из них 0»
      # — это утверждение про слой, и оно проверяемо, в отличие от молчания.
      # ⚠️ 198 / 177 → 199 / 178 (25.08.2026, задача 3.103): ручной слой получил
      # запись `artist`. Факт применён и наш, поэтому `unapplied` и `gaps`
      # не двинулись — ровно то различие, ради которого все четыре числа
      # печатаются рядом, а не одним итогом.
      # ⚠️ 199 / 178 → 200 / 179 (тот же день, задача 3.106): запись
      # `skill_focus` — на Сиале есть `Skill focus (Ride)` (замер AB1).
      # Та же арифметика: применён, наш, `unapplied` и `gaps` на месте.
      # ⚠️ 200 / 179 → 201 / 180 (26.08.2026, задача 3.108): тот же факт
      # у `epic_skill_focus` — эпического близнеца закрыл свой замер AB2.
      # Третий раз подряд та же арифметика; будь это дырой, двинулись бы
      # `unapplied` и `gaps`, а они стоят.
      # ⚠️ 201 / 180 → 202 / 181 (27.08.2026, задача 3.130): ручной слой
      # получил запись `devastating_critical` — машинное подтверждение
      # (`source.kind: "hak"`) уже применённого «отключён» одной МЕХАНИЧЕСКОЙ
      # ступенькой сверх машинного слоя (идемпотентно повторяет `disabled:
      # true`, которое там уже стоит). Факт применён и наш (то же самое число,
      # которое печатает страница), поэтому `unapplied` и `gaps` снова стоят —
      # четвёртый раз подряд одна и та же арифметика пополнения данных.
      assert {census.total, census.applied, census.unapplied, census.gaps} == {202, 181, 21, 0}

      # ⚠️ Отрицательный контроль к «ours не печатаем» ПЕРЕПИСАН 17.08.2026, и
      # прежняя форма была не просто неудачной, а обречённой. Он искал на
      # странице СТРОКУ «#{census.ours}» и держался только на том, что это
      # число нигде больше не встречается: `ours` было 178, `applied` 177. Гэп
      # `Improved evasion` снят — `ours` стало 177, то есть совпало с
      # `applied`, — и страница печатает это число совершенно законно
      # («Применены 177»). Числовой поиск при этом проверял не то утверждение:
      # запрещено не число, а КЛАИМ «В расчёт идут N», которым абзацы классов
      # и навыков объявляют свою классификацию, — у фитов её никто не делал,
      # там 177 это «один размеченный наш плюс 176 без метки».
      #
      # Проверяем сам клаим, и по всей странице тоже, чтобы перенос строки
      # в соседний абзац не прошёл: их ровно два, классы и навыки.
      #
      # ⚠️ 177 → 174 (17.08.2026, задача «фиты: use/requirements без
      # получателя»): три декоративных use-факта (lay_on_hands, smile_of_death,
      # teleportation) впервые размечены явно, и `ours` перестало совпадать
      # с `applied` (177) — тем не менее страница по-прежнему не печатает
      # `ours` ни в каком виде, только `total`/`applied`/`unapplied`/`gaps`
      # (все четыре не тронуты этой правкой, см. снимок 198/177/21/0 выше),
      # поэтому `refute`/`split` ниже не изменились ни на строку — падает
      # только числовое значение, которое страница и не показывает.
      #
      # ⚠️ 174 → 173 в тот же день (разметка `weapon_finesse/use` получателем
      # `counted_elsewhere`): четвёртый декоративный факт. Вывод абзаца выше
      # от этого не меняется ни на строку — страница `ours` не печатает вовсе,
      # и `refute`/`split` ниже проверяют клаим, а не число.
      #
      # ⚠️ 173 → 174 (25.08.2026, задача 3.103): применённая и размеченная запись
      # `artist`. Направление обратное четырём предыдущим сдвигам — там факт
      # уезжал из «наших» в «не наши», здесь прибавился наш, — а вывод абзаца
      # тот же и по той же причине: страница `ours` не печатает вовсе.
      # ⚠️ 174 → 175 (тот же день, задача 3.106): запись `skill_focus`, второй
      # прибавившийся наш применённый факт подряд. Вывод не меняется опять.
      # ⚠️ 175 → 176 (26.08.2026, задача 3.108): запись `epic_skill_focus`,
      # третий подряд. И в третий раз вывод тот же — страница `ours`
      # не печатает вовсе, а `refute`/`split` ниже проверяют клаим, не число.
      # ⚠️ 176 → 177 (27.08.2026, задача 3.130): запись `devastating_critical`,
      # четвёртый подряд применённый-и-наш факт (машинное подтверждение
      # уже применённого «отключён», source.kind: "hak"). Вывод тот же —
      # страница `ours` по-прежнему не печатает.
      refute feats =~ "В расчёт идут"
      assert length(String.split(render(view), "В расчёт идут")) == 3
      assert census.ours == 177
    end

    # ⚠️ Уменьшать число, СПРЯТАВ строки, запрещено — это подрыв механизма
    # честности (CLAUDE.md §9). Поэтому страница обязана назвать и остаток,
    # и то, про что он.
    test "остаток назван, а не умолчан, и категории перечислены", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      census = GapReceivers.census(Data.ruleset!())
      rest = render(element(view, "#sources-shard-not-ours"))

      # Все три слоя названы своим числом: остаток «76, 20 и 44», а не «140»,
      # по той же причине, по которой не складывается прочитанное. Навыки
      # присоединились 14.08.2026.
      assert rest =~ "#{census.classes.not_ours} фактов о классах"
      assert rest =~ "#{census.feats.not_ours} о фитах"
      assert rest =~ "#{census.skills.not_ours} о навыках"
      assert rest =~ "не убраны и не спрятаны"

      # Все категории до единой, по всем трём слоям, названные по-русски веб-слоем.
      for {receiver, _count} <-
            census.classes.not_our_receivers ++
              census.feats.not_our_receivers ++ census.skills.not_our_receivers do
        assert rest =~ Labels.gap_receiver(receiver),
               "категория #{receiver} не названа на странице"
      end

      # ...включая те, что Dan назвал сам, когда решал задачу.
      for word <- ~w(урон длительность иммунитеты призывы яды ловушки фамильяр баффы),
          do: assert(rest =~ word)
    end

    # ⚠️ Слой навыков, 14.08.2026 — читается ровно как абзац классов, потому
    # что размечен так же целиком (`labelled == total`), а не как абзац
    # фитов. До этой задачи здесь стоял тест «назван вместе с причиной, по
    # которой он не в счёте» — сам факт того, что он переписан, а не удалён,
    # и есть довод: слой существовал и раньше, просто без классификации.
    test "слой навыков назван своим абзацем и своими числами, как классы",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      census = GapReceivers.census(Data.ruleset!()).skills
      skills = render(element(view, "#sources-shard-skills"))

      assert skills =~ "прочитано #{census.total}"
      assert skills =~ "В расчёт идут #{census.ours}"
      assert skills =~ "#{census.applied} уже применены"
      assert skills =~ "#{census.gaps} пока нет"

      # Снимок: 54 / 54 / 9 / 8 / 1 — упадёт первым, если данные поедут.
      # ⚠️ Было 53 / 53 / 9 / 5 / 4 до 17.08.2026: ответ Dan на кейс P1 добавил
      # Алхимии факт про штраф брони (+1 к прочитанному) и сделал применёнными
      # оба её факта про значение навыка (+2 к нашим и к применённым).
      # Незакрытых оговорок это не тронуло — `gaps` тот же.
      # ⚠️ И тем же днём второе решение Dan («Режим скрытности = считай бафф»)
      # сняло ДВЕ записи с нашего получателя — `listen`/`spot`,
      # `rogue_stealth_penalty`, один факт, записанный дважды. Отсюда `ours`
      # 11 → 9 и `gaps` 4 → 2, а прочитанное и применённое не двинулись:
      # записи на месте и по-прежнему не применены.
      # ⚠️ И третьим ответом того же дня (замер про ловушки Теневого танцора)
      # `applied` 7 → 8, `gaps` 2 → 1: `craft_trap / class_skills` перестал быть
      # `unclear` и стал правилом. ⚠️ `ours` при этом НЕ двинулся — в отличие
      # от правки строкой выше, где двигался именно он. Два соседних числа
      # в одном снимке за один день изменились по разным причинам: там факт
      # перестал быть нашим, здесь наш факт стал посчитанным.
      # ⚠️ 22.08.2026 (задача 3.78): `applied` 8 → 9, `gaps` 1 → 0, и `ours`
      # снова не двинулся. Причина ТРЕТЬЯ по счёту в этом абзаце: факт
      # `set_trap / class_skills_unchanged` не стал ни чужим, ни посчитанным —
      # он утверждал СОВПАДЕНИЕ с ванилью, и загрузчик теперь его сверяет.
      # ⚠️ Абзац на странице «Источники» от этого говорит «0 пока нет», и это
      # первый день, когда у слоя навыков ноль незакрытых оговорок. Строка
      # остаётся на странице: «ноль» и «мы про это не пишем» — разные фразы.
      assert {census.total, census.labelled, census.ours, census.applied, census.gaps} ==
               {54, 54, 9, 9, 0}

      assert census.reported?
    end

    # Сторож русских подписей: получатель, законно добавленный в данные и
    # не названный в `Labels`, напечатался бы английским id — видимо, но
    # по-английски посреди русской фразы. Это единственный зазор, который
    # не закрывает сторож загрузчика.
    test "у каждого получателя из словаря данных есть русская подпись" do
      vocabulary = GapReceivers.vocabulary(Data.ruleset!())

      for receiver <- MapSet.union(vocabulary.our, vocabulary.not_our) do
        assert Labels.gap_receiver(receiver) != receiver,
               "получатель #{receiver} не назван по-русски в Labels"
      end

      # Положительный контроль: неизвестный id проверка ловит, а не пропускает.
      assert Labels.gap_receiver("damge") == "damge"
    end

    test "объявляет share-alike для нашего производного слоя", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      page = render(view)

      assert page =~ "переработан"
      assert page =~ "производн"
      assert page =~ "share-alike"
    end

    test "оговорка о неаффилированности и товарных знаках", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      disclaimer = render(element(view, "#sources-disclaimer"))

      assert disclaimer =~ "не связан"
      assert disclaimer =~ "BioWare"
      assert disclaimer =~ "Beamdog"
      assert disclaimer =~ "Wizards of the Coast"
      assert disclaimer =~ "администрацией шарда"
      assert disclaimer =~ "товарные знаки"
    end

    test "вики Сиалы не упомянута нигде на странице", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/sources")
      page = render(view)

      refute page =~ "wiki.siala"
      refute page =~ "siala.kiev.ua"
      refute page =~ "вики Сиалы"
      refute page =~ "вики шарда"
    end
  end

  describe "чужая группа не открывает путь к футеру в обход доступа" do
    setup :register_and_log_in_user

    test "лента чужой группы уводит на /groups, а не показывает страницу", %{conn: conn} do
      other_group = group_fixture(user_scope_fixture())

      assert {:error, {:live_redirect, %{to: "/groups"}}} =
               live(conn, ~p"/library/group/#{other_group}")
    end
  end

  defp assert_footer(view) do
    assert has_element?(view, "#site-footer")
    assert has_element?(view, "#footer-fandom-link")
    assert has_element?(view, "#footer-license-link")
    assert has_element?(view, "#footer-sources-link")
  end
end
