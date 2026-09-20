defmodule BuildCalculatorWeb.BuilderMiniSetsTest do
  @moduledoc """
  Зона «Мини-сеты» блока «Вещи» — задача 3.185.

  Dan, 11.09.2026: «надо будет указать, что из минисета 1 у нас 2 куска,
  из минисета 2 у нас 3 куска, из минисета 3 у нас 2 куска, etc».

  Три вещи здесь важнее остального, и все три названы постановкой как
  обязательные к ВИДИМОСТИ — иначе расчёт выглядит сломанным:

    * 🔴 строка с ОДНИМ куском не считается вовсе (`[1,1] → Nmini 0`), и
      причина стоит рядом со строкой (CLAUDE.md §6: недоступное показываем
      с причиной, а не молчанием);
    * 🔴 максимальному билду мини-сеты к оружейным и расовым бонусам не дают
      НИЧЕГО — он в капе исполнителя и без них, и это надо прочитать;
    * сумма кусков сверх слотов ПРЕДУПРЕЖДАЕТ и НЕ БЛОКИРУЕТ — расшаренная
      ссылка может нести что угодно и обязана открываться (та же линия, что
      у щита со вторым оружием, задача 3.132).

  ⚠️ Арифметика `Nmini` здесь НЕ переоткрывается — она под
  `test/build_calculator/rules/mini_sets_test.exs` (задача 3.184). Здесь
  только то, что зона показывает и что её органы управления делают с билдом.
  """

  use BuildCalculatorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  # Все пять сиальских владений сразу: кейсы этого файла про усиление и про
  # интерфейс, а не про допуск к оружию (это `builder_gear_weapon_test.exs`),
  # и отказ по владению превратил бы половину из них в ложно-зелёные нули.
  # Тот же приём, что в `mini_sets_test.exs` ядра.
  @proficiencies [
    :siala_blade_proficiency,
    :siala_polearm_proficiency,
    :siala_ranged_proficiency,
    :siala_axe_proficiency,
    :siala_hammer_proficiency
  ]

  setup do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  defp open(conn, build) do
    {:ok, view, html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
    view |> element("#gear-toggle") |> render_click()
    {view, html}
  end

  # Светлый эльф 40, лук в руках. Раса и оружие взяты не для красоты: ровно
  # на этом билде расовый бонус и бонус за тип оружия ненулевые, то есть
  # мини-сетам есть что усиливать, — и ровно он стоит в таблице задачи 3.184.
  #
  # `sagra?` решает, максимальный это билд или нет: чистые классы Сагры дают
  # 9 + 9 = 18 и упираются в кап исполнителя БЕЗ всяких кусков, а один уровень
  # барда выводит билд из группы и оставляет 6 + 6 = 12 — то есть место
  # для роста.
  # `named` — крафтовые (именные) вещи (задача 3.203, второй вход счёта HP);
  # по умолчанию 0, чтобы не трогать вызовы, которым он не нужен.
  defp elf(sets, sagra?, named \\ 0) do
    levels =
      if sagra?,
        do: List.duplicate(:fighter, 40),
        else: List.duplicate(:fighter, 39) ++ [:bard]

    Build.new(
      ruleset_version: "siala_41",
      race: :half_elf,
      alignment: :true_neutral,
      base_abilities: %{str: 16, dex: 14, con: 14, int: 12, wis: 12, cha: 10},
      levels: levels,
      gear: Gear.new(weapon: :longbow, feats: @proficiencies, mini_sets: sets, named_items: named)
    )
  end

  describe "зона и её органы управления" do
    test "у билда без мини-сетов зона есть, а строк в ней нет", %{conn: conn} do
      {view, _html} = open(conn, elf([], false))

      assert has_element?(view, "#gear-zone-mini-sets")
      refute has_element?(view, "#gear-mini-set-list")
      assert has_element?(view, "#gear-mini-set-add")

      # И ни одной жалобы: пустая зона — обычное состояние, а не проблема.
      refute has_element?(view, "#gear-issues")
    end

    # Новая строка начинается с ОДНОГО куска, а не с двух: один кусок —
    # законное состояние («набор надет, собран не полностью»), и строка сразу
    # называет причину, по которой он не в счёт. Так зона учит главной ловушке
    # правила вместо того, чтобы прятать её за уже «правильным» умолчанием.
    test "«+ Добавить набор» заводит строку с одним куском", %{conn: conn} do
      {view, _html} = open(conn, elf([], false))

      view |> element("#gear-mini-set-add") |> render_click()

      assert has_element?(view, "#gear-mini-set-0")
      assert render(element(view, "#gear-mini-set-count-0")) =~ "1"
      assert has_element?(view, "#gear-mini-set-why-0")
    end

    test "степпер двигает число, а не пересобирает список", %{conn: conn} do
      {view, _html} = open(conn, elf([2, 3], false))

      view |> element("#gear-mini-set-more-0") |> render_click()

      assert render(element(view, "#gear-mini-set-count-0")) =~ "3"

      # Соседняя строка не тронута — правка адресована СВОЕЙ позиции.
      assert render(element(view, "#gear-mini-set-count-1")) =~ "3"

      view |> element("#gear-mini-set-less-0") |> render_click()
      assert render(element(view, "#gear-mini-set-count-0")) =~ "2"
    end

    # Пол — один кусок, а не ноль: убрать строку это «×», отдельное действие.
    # Ноль был бы третьим состоянием, неотличимым от «строки нет» ни в билде,
    # ни в ссылке.
    test "«−» не опускает ниже одного куска и там заблокирован", %{conn: conn} do
      {view, _html} = open(conn, elf([1], false))

      assert view |> element("#gear-mini-set-less-0") |> render() =~ "disabled"
    end

    test "«×» снимает свою строку, остальные остаются на месте", %{conn: conn} do
      {view, _html} = open(conn, elf([2, 5], false))

      view |> element("#gear-mini-set-drop-0") |> render_click()

      assert render(element(view, "#gear-mini-set-count-0")) =~ "5"
      refute has_element?(view, "#gear-mini-set-1")
    end

    # Правка едет в ссылку той же воронкой, что и всё остальное (`put_build/2`),
    # то есть кусками можно поделиться — это и было главной недостачей: до
    # задачи 3.185 ссылка мини-сеты не переносила вовсе.
    test "правка кусков доезжает до адреса, и по нему билд открывается тем же",
         %{conn: conn} do
      {view, _html} = open(conn, elf([2], false))

      view |> element("#gear-mini-set-more-0") |> render_click()
      path = assert_patch(view)

      assert {:ok, %{build: %Build{} = build}} = Encoding.decode(code_from_path(path))
      assert build.gear.mini_sets == [3]

      # И по этому адресу зона открывается с теми же тремя кусками — то есть
      # кусками можно ПОДЕЛИТЬСЯ, а это и было главной недостачей: до задачи
      # 3.185 ссылка их не переносила вовсе.
      {:ok, reopened, _html} = live(conn, path)
      reopened |> element("#gear-toggle") |> render_click()
      assert render(element(reopened, "#gear-mini-set-count-0")) =~ "3"
    end

    # Ванильному ruleset'у зона не достаётся вовсе: мини-сетов в NWN нет,
    # как нет ни расового бонуса шарда, ни бонуса за тип оружия
    # (`Rules.MiniSets.gaps/2` — там же довод, почему и оговорки там нет).
    test "у ванили зоны нет", %{conn: conn} do
      %Build{} = siala = elf([], false)
      build = %Build{siala | ruleset_version: "vanilla"}
      {view, _html} = open(conn, build)

      refute has_element?(view, "#gear-zone-mini-sets")
    end
  end

  describe "строка с одним куском не считается — и говорит об этом" do
    test "причина стоит у строки и в сводке предупреждений", %{conn: conn} do
      {view, _html} = open(conn, elf([1, 1], false))

      assert render(element(view, "#gear-mini-set-why-0")) =~ "в счёт не идёт"
      assert render(element(view, "#gear-mini-set-why-1")) =~ "в счёт не идёт"

      # Третий список экрана (задача 3.133) — «то, что ТЫ ввёл, конфликтует».
      assert has_element?(view, "#gear-issue-refused-mini-set-0")
      assert has_element?(view, "#gear-issue-refused-mini-set-1")
    end

    # ⚠️ `Nmini` ноль при двух надетых вещах — ровно то число, которое без
    # объяснения читается как поломка. Обе половины стоят рядом: сколько
    # НАБРАНО и сколько ПОШЛО в счёт.
    #
    # 🔴 И между ними НЕ «=» (задача 3.190): числа расходятся всегда, когда
    # есть одиночка или перебор слотов, и знак равенства печатал бы ложь —
    # ровно на этом билде («набрано 2 = в счёт 0»), и ещё на четырёх
    # из девяти раскладок, которыми 3.190 мерила зону. Правило — из соседнего `.gear-total`
    # (`#gear-ac-total`, комментарий в разметке): «Строка, не равная своему
    # итогу, хуже отсутствующей». Проверяется по ТЕКСТУ, а не по разметке:
    # в HTML знак равенства стоит в каждом атрибуте.
    test "«кусков набрано 2 → в счёт 0» напечатано словами, без ложного равенства",
         %{conn: conn} do
      {view, _html} = open(conn, elf([1, 1], false))

      text =
        view
        |> element("#gear-mini-set-pieces")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.text()

      assert text =~ "набрано"
      assert text =~ "2"
      assert text =~ "0"
      assert text =~ "→"
      refute text =~ "="
    end

    # Положительный контроль: у набора из двух кусков ни причины, ни строки
    # в сводке нет — иначе предыдущие проверки зеленели бы на любом вводе.
    test "набор из двух кусков причины не получает", %{conn: conn} do
      {view, _html} = open(conn, elf([2], false))

      refute has_element?(view, "#gear-mini-set-why-0")
      refute has_element?(view, "#gear-issue-refused-mini-set-0")
    end

    # Клик по находке в сводке ведёт к СВОЕЙ строке и открывает «Вещи» —
    # тот же приём, что у остальных находок (`jump_to_gear_issue`,
    # задача 3.133). На мобильном тем же событием открывается шторка «Итого»
    # (`gear_issue_jump/1` в шаблоне) — иначе прокрутка шла бы невидимо
    # внутри полоски ~88px.
    test "клик по находке ведёт к своей строке", %{conn: conn} do
      {view, _html} = open(conn, elf([2, 1], false))

      view |> element("#gear-issue-refused-mini-set-1") |> render_click()

      assert has_element?(view, "#gear-body")
      assert_push_event(view, "scroll_to_section", %{id: "gear-mini-set-1"})
    end
  end

  describe "максимальному билду куски не дают ничего — и это сказано" do
    # 🔴 Главное, ради чего блок «Из этого следует» в зоне вообще есть: игрок,
    # надевший десять кусков и не увидевший роста AB, должен прочитать ПОЧЕМУ,
    # а не решить, что калькулятор врёт.
    test "строка получателя печатается даже при нулевой прибавке", %{conn: conn} do
      {view, _html} = open(conn, elf([5, 5], true))

      row = render(element(view, "#gear-mini-set-effect-attack_bonus"))

      assert row =~ "AB"
      assert row =~ "+18"
      assert row =~ "потолок"

      # И в сводке — своей строкой разряда «срезано потолком».
      assert has_element?(view, "#gear-issue-capped-mini-set-cap-attack_bonus")
    end

    # Тот же билд БЕЗ Сагры и с меньшим числом кусков: место для роста есть,
    # и тогда строка показывает рост, а слова «потолок» в ней нет. Без этого
    # контроля проверка выше зеленела бы у зоны, которая печатает «потолок»
    # всегда.
    #
    # ⚠️ Кусков именно ЧЕТЫРЕ, и это поправлено прогоном, а не прикинуто:
    # на десяти кусках потолок кусает и несагровика тоже (12 + 12 = 24 при
    # капе 18), то есть «не максимальный билд» и «потолок не кусает» — разные
    # утверждения, и второе уже не следует из первого, как только кусков
    # достаточно много.
    test "у билда с запасом строка показывает рост, без слова «потолок»", %{conn: conn} do
      {view, _html} = open(conn, elf([2, 2], false))

      row = render(element(view, "#gear-mini-set-effect-attack_bonus"))

      assert row =~ "+12"
      assert row =~ "+16"
      refute row =~ "потолок"
      refute has_element?(view, "#gear-issue-capped-mini-set-cap-attack_bonus")
    end

    # Разбор AB в панели итогов обязан СХОДИТЬСЯ со своим итогом: до задачи
    # 3.185 терм усиления в него не входил вовсе, и у этого билда сумма
    # термов давала 46 при AB 50 (найдено прогоном, не чтением).
    test "разбор AB несёт терм усиления", %{conn: conn, ruleset: ruleset} do
      build = elf([2, 2], false)
      {view, _html} = open(conn, build)

      stats = Rules.compute(build, ruleset)
      assert stats.mini_set_attack_bonus == 4

      terms = BuildCalculatorWeb.Builder.Summary.ab_terms(ruleset, stats)
      assert Enum.any?(terms, &(&1.label == "Мини-сеты" and &1.value == "+4"))

      assert terms
             |> Enum.map(fn %{value: v} ->
               v |> String.replace("+", "") |> String.to_integer()
             end)
             |> Enum.sum() == stats.attack_bonus

      # И это видно на экране, а не только в функции.
      assert render(view) =~ "Мини-сеты"
    end
  end

  describe "сумма сверх слотов предупреждает и не блокирует" do
    test "предупреждение названо числами, а ввод не отобран", %{conn: conn, ruleset: ruleset} do
      build = elf([6, 5, 3], true)
      {view, _html} = open(conn, build)

      note = render(element(view, "#gear-mini-sets-over"))
      assert note =~ "14"
      assert note =~ "11"

      # Не блокирует: строки на месте, степперы живы, и «+» ещё работает.
      assert has_element?(view, "#gear-mini-set-more-0")
      view |> element("#gear-mini-set-more-0") |> render_click()
      assert render(element(view, "#gear-mini-set-count-0")) =~ "7"

      # Срезает сумму ядро, а не форма.
      assert Rules.compute(build, ruleset).mini_set_pieces == 11

      # И сводка называет находку своим разрядом.
      assert has_element?(view, "#gear-issue-capped-mini-set-over")
    end

    test "билд в пределах слотов предупреждения не получает", %{conn: conn} do
      {view, _html} = open(conn, elf([5, 5], false))

      refute has_element?(view, "#gear-mini-sets-over")
      refute has_element?(view, "#gear-issue-capped-mini-set-over")
    end
  end

  describe "прибавка к HP — своя строка этой зоны (задача 3.203)" do
    # Числа — прогоном `Rules.compute/2` на этом же билде (Светлый эльф-воин
    # 40, CON 14), а не прикидкой: они же стоят в `systems.json`
    # (`hp_percent_by_item_count`) как «10 кусков дают 1107 при базе 540».
    test "«было → стало» и процент — на десяти кусках", %{conn: conn} do
      {view, _html} = open(conn, elf([10], true))

      row = render(element(view, "#gear-mini-set-effect-hp"))

      assert row =~ "HP"
      assert row =~ "540"
      assert row =~ "1107"
      assert row =~ "+567"
      assert row =~ "+105%"
      refute row =~ "крафт"
    end

    # Второй вход того же счёта (крафтовые вещи) даёт ОДНУ строку с кусками,
    # а не свою, и подпись называет его вслух — иначе билд с двумя кусками
    # и тремя крафтовыми вещами показывал бы 45%, будто их дали одни куски.
    test "крафтовые вещи входят в тот же счёт, и подпись это называет", %{conn: conn} do
      {view, _html} = open(conn, elf([2], false, 3))

      row = render(element(view, "#gear-mini-set-effect-hp"))

      assert row =~ "536"
      assert row =~ "777"
      assert row =~ "+45%"
      assert row =~ "с 3 крафтовыми"
    end

    # На одиннадцатой вещи общего счёта прибавка ОБРЫВАЕТСЯ в ноль — молчаливый
    # «+0» здесь читался бы как «сеты ничего не дают», а не как «счёт ушёл за
    # таблицу» (CLAUDE.md §6). Слово то же, что у соседней зоны «Крафт»
    # (`#gear-named-items-bonus`, «обрыв, +0% HP»).
    test "обрыв счёта называется словом, а не тихим нулём", %{conn: conn} do
      {view, _html} = open(conn, elf([10], true, 1))

      row = render(element(view, "#gear-mini-set-effect-hp"))

      assert row =~ "обрыв"
      assert row =~ "+0"
      refute row =~ "+105%"
    end

    # Без единого куска в счёте (набор не введён вовсе) строки нет — билд
    # с одними крафтовыми вещами уже назван в зоне «Крафт», второе место для
    # того же числа здесь было бы лишним («три числа об одном», 3.156).
    test "без кусков в счёте строки нет — она остаётся в зоне «Крафт»", %{conn: conn} do
      {view, _html} = open(conn, elf([], true, 5))

      refute has_element?(view, "#gear-mini-set-effect-hp")
      assert render(element(view, "#gear-named-items-bonus")) =~ "45%"
    end

    # Одинокий кусок (`[1]`) НЕ идёт в счёт (`Nmini = 0`) — тот же случай,
    # что у AB/AC/навыков рядом, только для HP.
    test "одинокий кусок не идёт в счёт — строки нет", %{conn: conn} do
      {view, _html} = open(conn, elf([1], false))

      refute has_element?(view, "#gear-mini-set-effect-hp")
    end

    # Положительный контроль на плашку «нечего усиливать»: при пустых
    # AB/AC/навыках, но с кусками, дающими HP, плашка обязана остаться
    # СКОУПЛЕННОЙ к оружию и расе — иначе игрок читает «ничего не растёт»
    # рядом со строкой, которая только что показала рост HP.
    test "плашка «нечего усиливать» не противоречит соседней строке HP", %{conn: conn} do
      # Кусков мало, а класс не Сагры — АB/AC/навыки могут остаться нулевыми
      # на части уровней, но при 40 уровнях светлого эльфа с луком расовый
      # и оружейный термы уже ненулевые, поэтому берём билд без оружия в
      # руках вовсе, чтобы список AB/AC/навыков был пуст, а HP всё равно рос.
      %Build{} = base = elf([5, 5], false)
      build = %Build{base | gear: Gear.new(mini_sets: [5, 5])}
      {view, _html} = open(conn, build)

      assert has_element?(view, "#gear-mini-set-idle")
      assert render(element(view, "#gear-mini-set-idle")) =~ "Бонусы за тип оружия и расу"
      assert has_element?(view, "#gear-mini-set-effect-hp")
    end
  end

  # Код билда из адреса, который LiveView запатчил, — та же дорога, которой
  # пользуется `builder_live_test.exs`: читаем то, что окажется в адресной
  # строке игрока, а не внутренний ассайн.
  defp code_from_path(path) do
    [_, code] = Regex.run(~r/[?&]b=([A-Za-z0-9._-]+)/, path)
    code
  end
end
