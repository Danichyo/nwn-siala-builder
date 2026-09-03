defmodule BuildCalculatorWeb.BuildViewGuideTest do
  @moduledoc """
  Экран просмотра как **гид по прокачке** — задача 3.24, решение Dan 10.08.2026:
  «когда берешь уровень в игре, надо зайти в билд и посмотреть что же надо
  прокачать… при прокачке итоговые статы уже не интересны, они уже известны».

  Проверяется три вещи, и все три — про порядок и плотность, а не про наличие:

  1. **гид стоит ПЕРЕД итогами** — порядок в DOM, через CSS-комбинатор `~`,
     а не «оба элемента есть»: последнее было бы зелёным и при прежней вёрстке;
  2. **флаг возвращает прежний порядок** — отрицательный контроль механизма.
     Без него утверждение «гид первый» доказывало бы только то, что оба блока
     на странице, а не то, что порядком управляет флаг;
  3. **ничего из обязательного не потерялось** — легенда, `gaps`, пометка про
     неполноту правил, разбор у каждого крупного числа, футер с атрибуцией.
     Это то, что постановка §3.24 назвала «нельзя потерять», и проверяется оно
     в обоих положениях флага: перестановка секций — ровно та правка, которая
     умеет тихо унести блок вместе с секцией.

  ⚠️ `async: false` — тесты меняют глобальный `Application.put_env/3`, и
  параллельный сосед увидел бы чужой порядок секций.
  """
  use BuildCalculatorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Layouts

  setup do
    ruleset = Data.ruleset!()

    # Сторож: если кто-то выключит флаг в конфиге, а не в тесте, «гид первый»
    # покраснеет осмысленно, а не «элемент не найден».
    assert Layouts.guide_first?()

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

    on_exit(fn -> Application.put_env(:build_calculator, :guide_first, true) end)

    %{ruleset: ruleset, build: build, code: Encoding.encode(build)}
  end

  # Задача 3.147: `○` по умолчанию скрыт (решение Dan — «выключить по
  # дефолту, чтобы разгрузить UI», тот же довод, что у конструктора, 3.146).
  # Большинство тестов этого файла писаны ДО переключателя и проверяют, что
  # выданное классом рендерится ВЕРНО, когда его смотрят, — этот факт
  # по-прежнему нужно знать, только теперь после явного клика по
  # `#view-granted-checkbox`. Один клик, а не отдельная сборка страницы:
  # `render_click/1` возвращает свежий HTML, но `view` тот же процесс.
  defp open_with_granted(conn, path) do
    {:ok, view, _html} = live(conn, path)
    view |> element("#view-granted-checkbox") |> render_click()
    {:ok, view, render(view)}
  end

  describe "порядок секций" do
    # `~` — «следующий сиблинг где-то дальше». Именно это и надо проверить:
    # «оба блока есть» было бы зелёным и до правки.
    test "гид стоит перед итогами, характеристиками и навыками", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-guide ~ #view-stats")
      assert has_element?(view, "#view-guide ~ #view-abilities")
      assert has_element?(view, "#view-guide ~ #view-picks")

      # И обратного порядка нет — иначе селектор выше мог бы совпасть на
      # странице, где секции продублированы.
      refute has_element?(view, "#view-stats ~ #view-guide")
    end

    test "флаг возвращает прежний порядок — итоги первыми", %{conn: conn, code: code} do
      Application.put_env(:build_calculator, :guide_first, false)

      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-stats ~ #view-guide")
      refute has_element?(view, "#view-guide ~ #view-stats")

      # Гид не исчез и не продублировался: секция ровно одна в обоих положениях.
      assert has_element?(view, "#view-guide")
      assert has_element?(view, "#view-guide-level-1")
      assert has_element?(view, "#view-guide-level-41")
    end

    test "гид не дублируется — секция одна, а не две", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # `#view-guide-0` — первая колонка гида. Продублированная секция дала бы
      # два элемента с одним id, и `element/2` упал бы на неоднозначности.
      assert render(element(view, "#view-guide-0")) =~ "view-guide-level-1"
      refute has_element?(view, "#view-guide ~ #view-guide")
    end
  end

  describe "плотность гида" do
    test "уровень, где нечего выбирать, помечен и несёт прочерк", %{
      conn: conn,
      ruleset: ruleset
    } do
      # На 2-м уровне воина не выбирается ничего: общий фит даётся на 1, 3, 6…,
      # прибавка к характеристике — на кратных 4 (`ruleset.epic`), а бонусный
      # слот воина — на чётных, поэтому его занимаем сами, чтобы 2-й остался
      # «пустым» именно по отсутствию выбора, а не по нашей забывчивости.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 5),
          feats: %{
            1 => %{:general => :toughness, {:class_bonus, :fighter} => :power_attack},
            2 => %{{:class_bonus, :fighter} => :cleave}
          }
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      # Положительный контроль рядом: на 2-м выбор есть, на 5-м нет.
      refute has_element?(view, "#view-guide-level-2[data-empty='1']")
      assert has_element?(view, "#view-guide-level-5[data-empty='1']")
      assert render(element(view, "#view-guide-level-5")) =~ "—"
      assert render(element(view, "#view-guide-legend")) =~ "выбирать нечего"
    end

    test "выданное классом — одной строкой, но каждое имя со своим id", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{code}")

      # Один `.pick[data-granted]` на уровень вместо строки на каждый фит:
      # на 1-м уровне воина выдач несколько, а блок один.
      assert has_element?(view, "#view-guide-level-1 .pick[data-granted='1'] .v-g-granted")

      # Имена целы и адресуемы поимённо — счётчик без имён здесь запрещён
      # (плашку «от класса ×N» убрали с карточки класса ровно за это).
      assert has_element?(view, "#view-guide-level-1-granted-toughness")
      assert render(element(view, "#view-guide-level-1-granted-toughness")) =~ "Toughness"
    end

    # ⚠️ Выбор виден ВЕЗДЕ, где видно имя фита (CLAUDE.md §6). Тест проверял это
    # на ВЫДАННОМ фите (`granted_choices`, задача 3.26); замеры M2/M2b
    # (14.08.2026) показали, что `Weapon of choice` классом не выдаётся —
    # он берётся слотом. Проверка осталась той же по смыслу и переехала
    # на слотовую строку: имя фита без оружия не отвечает на вопрос
    # «что мне качать», ради которого этот экран и переставили.
    test "у фита с выбором в гиде напечатано выбранное", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28),
          base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
          feats: %{
            1 => %{general: {:weapon_focus, :scimitar}},
            14 => %{{:class_bonus, :weapon_master} => {:weapon_of_choice, :scimitar}}
          }
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      row = render(element(view, "#view-guide-level-14"))

      assert row =~ "Weapon of choice"
      assert row =~ "Scimitar"
    end

    # ⚠️ Запятая обязана быть ТЕКСТОМ, а не `content` из CSS: гид держат открытым
    # рядом с игрой и из него копируют, а `::after` в буфер обмена не попадает —
    # уезжало бы «Deflect arrowsWholeness of body». Первая реализация была именно
    # такой, и в браузере выглядела правильно.
    test "имена выданного разделены запятой в разметке, а не в CSS", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:monk, 5),
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")

      level =
        Enum.find(1..5, fn level ->
          has_element?(view, "#view-guide-level-#{level} .v-g-granted") and
            view
            |> element("#view-guide-level-#{level} .v-g-granted")
            |> render()
            |> LazyHTML.from_fragment()
            |> LazyHTML.query(".v-g-granted > span")
            |> Enum.count() > 1
        end)

      assert level, "у монаха 1–5 нет уровня с двумя выдачами — фикстуру надо менять"
      row = render(element(view, "#view-guide-level-#{level}"))
      assert row =~ ", "

      # И запятая стоит между именами, а не приклеена к первому: перед ней нет
      # пробела (эта ошибка уже была — «Increased multiplier , Superior focus»).
      refute row =~ " , "
    end

    test "прочерка нет там, где класс что-то выдал", %{conn: conn, ruleset: ruleset} do
      # У воина 1-й уровень несёт и выбор, и выдачу; ищем уровень, где выбора
      # нет, а выдача есть, — у монаха такие бывают. Если у конкретного ruleset
      # такого уровня нет вовсе, тест честно ничего не утверждает и это видно.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:monk, 12),
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, html} = open_with_granted(conn, ~p"/b/#{Encoding.encode(build)}")
      assert html =~ "view-guide-level-1"

      passive =
        Enum.find(2..12, fn level ->
          has_element?(view, "#view-guide-level-#{level} .pick[data-granted='1']") and
            not has_element?(view, "#view-guide-level-#{level} .pick[data-abil='1']") and
            not has_element?(view, "#view-guide-level-#{level} .pick[data-wasted='1']")
        end)

      assert passive, "у монаха 1–12 нет ни одного уровня с выдачей — фикстуру надо менять"
      refute render(element(view, "#view-guide-level-#{passive}")) =~ "v-g-none"
    end

    # Зеркало теста выше, задача 3.147. Тот же билд и тот же «пассивный»
    # уровень (единственное содержимое которого — выдача), но БЕЗ клика по
    # переключателю — то есть в состоянии по умолчанию. Скрытая выдача не
    # оставляет правую половину строки пустой: `nothing_at_all?/2` считает
    # такой уровень «нет вообще ничего», ровно как если бы класс не выдал
    # ничего, и печатает прочерк — иначе строка выглядела бы сбоем вёрстки
    # (комментарий у `<span :if={nothing_at_all?(...)}>` в build_view_live.ex).
    test "прочерк ПОЯВЛЯЕТСЯ на том же уровне, когда переключатель прячет выдачу", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:monk, 12),
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      # Найден клика ради — открыт переключатель, чтобы найти тот же «пассивный»
      # уровень (иначе data-granted у него не отрендерится вовсе), затем
      # переключатель возвращается в дефолт, и проверяется именно он.
      view |> element("#view-granted-checkbox") |> render_click()

      passive =
        Enum.find(2..12, fn level ->
          has_element?(view, "#view-guide-level-#{level} .pick[data-granted='1']") and
            not has_element?(view, "#view-guide-level-#{level} .pick[data-abil='1']") and
            not has_element?(view, "#view-guide-level-#{level} .pick[data-wasted='1']")
        end)

      assert passive, "у монаха 1–12 нет ни одного уровня с выдачей — фикстуру надо менять"

      view |> element("#view-granted-checkbox") |> render_click()

      assert render(element(view, "#view-guide-level-#{passive}")) =~ "v-g-none"
      refute has_element?(view, "#view-guide-level-#{passive} .pick[data-granted='1']")
    end

    test "номер уровня — ссылка на самого себя: «мой уровень» без состояния", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # Вариант «блок мой следующий уровень» из постановки требовал состояния;
      # ссылка на собственный id даёт то же самое даром — `:target` подсвечивает
      # строку, а уровень выбрал сам читатель.
      assert has_element?(view, "#view-guide-level-24 a[href='#view-guide-level-24']")
      assert has_element?(view, "#view-guide-level-24 a[aria-label='Уровень 24']")
    end
  end

  describe "то, что нельзя потерять — в обоих положениях флага" do
    for {name, flag} <- [{"гид первым", true}, {"итоги первыми", false}] do
      test "#{name}: разбор есть у каждого крупного числа", %{conn: conn, code: code} do
        Application.put_env(:build_calculator, :guide_first, unquote(flag))
        {:ok, view, _html} = live(conn, ~p"/b/#{code}")

        # Задача 3.6: без разбора шаренный билд снова становится списком цифр.
        for key <- ~w(hp ac bab ab fort ref will) do
          assert has_element?(view, "#view-stat-#{key} .v-terms"),
                 "у карточки #{key} нет разбора списком"
        end

        # Прозой — только там, где сумма невозможна: «Атак / раунд» это поиск
        # по таблице, а не сумма (`Summary.apr_caption/1`).
        assert has_element?(view, "#view-stat-apr .from")
        refute has_element?(view, "#view-stat-apr .v-terms")

        # У характеристик разбор свой и на месте.
        assert has_element?(view, "#view-ability-str .from")
      end

      test "#{name}: пометка про неполноту правил, gaps, легенда и футер на месте", %{
        conn: conn,
        code: code
      } do
        Application.put_env(:build_calculator, :guide_first, unquote(flag))
        {:ok, view, _html} = live(conn, ~p"/b/#{code}")

        # Задача 3.147: `○` по умолчанию скрыт, а строка легенды про него —
        # ровно тем же переключателем; открываем его, чтобы проверить, что
        # легенда всё ещё называет `○`, когда он есть на экране.
        view |> element("#view-granted-checkbox") |> render_click()

        # ⚠️ Задача 3.49 (18.08.2026): было «перенесены не полностью» — заголовок
        # считал решённые споры источников и процитированные константы дырами
        # наравне с настоящими (`BuildCalculatorWeb.Builder.Gaps.tier/1`).
        #
        # 🔴 Задача 3.88 (24.08.2026, решение Dan) — ПЕРЕСМОТР: «и с экрана
        # просмотра и в экспорте прячем тоже». Здесь стояло «реальных дыр
        # стало НОЛЬ, и заголовок… печатать нельзя, тест держит то, что
        # блок… говорит, что числа не окончательные» (задача 3.86, тот же
        # день) — верно было только про заголовок «ещё не в расчёте», а не
        # про факт наличия какой-то фразы о неполноте вообще. 3.88 убрала
        # и вторую ветку («числа не окончательные» без счётчика): блок
        # `#view-gaps` остаётся (в нём список гэпов ЭТОГО билда), а баннер
        # про правила Сиалы — нет, пока настоящих дыр нет.
        #
        # ⚠️ Задача 3.148 (31.08.2026): держала блок на экране БЕЗУСЛОВНО
        # строка «база билда, без экипировки» — снята, и вместе с ней
        # `#view-gaps` получил свой гейт (`data_real_count > 0 or
        # build_count > 0`). У фикстуры этого файла (без оружия в руках)
        # есть свой гэп билда, поэтому блок остаётся — списком, а не
        # безусловной строкой; см. `build_view_live_test.exs`, describe
        # «honesty», тот же довод разобран подробнее.
        gaps_note = render(element(view, "#view-gaps"))
        refute gaps_note =~ "Часть правил Сиалы"
        refute gaps_note =~ "ещё не в расчёте"
        assert has_element?(view, "#view-gaps-list")
        assert gaps_note =~ "не смогло посчитать"
        assert render(element(view, "#view-guide-legend")) =~ "выдан классом"

        # ⚠️ Легенда гида называет всё, что в гиде встречается, — включая ★,
        # который до 10.08.2026 (снятие переписи фитов) был виден только там.
        assert render(element(view, "#view-guide-legend")) =~ "эпический фит"

        # 🔴 03.09.2026 (задача 3.175) вернула ВТОРУЮ легенду — не дубль
        # снятой переписи, а легенду компактного списка фитов внизу файла
        # (`#view-feats`, свой собственный `#view-feats-legend`), у которой
        # те же символы и та же цитата, что у гида, потому что это один
        # и тот же факт в разных блоках (комментарий у самой разметки).
        # Прежнее «легенда осталась ОДНА» верно описывало состояние
        # 10.08–02.09.2026 и больше не верно.
        assert render(element(view, "#view-feats-legend")) =~ "эпический фит"

        # И секция навыков жива — иначе `refute` выше был бы зелёным и на
        # странице, где снесли всю секцию, а не только фиты.
        assert has_element?(view, "#view-picks #view-skills")

        # CC BY-SA — требование третьей стороны, не украшение.
        assert has_element?(view, "#site-footer #footer-fandom-link")
        assert has_element?(view, "#site-footer #footer-sources-link")
      end
    end

    # ⚠️ `ul` внутри `p` — невалидный HTML: браузер закрывает параграф ПЕРЕД
    # списком, и список выпадает из блока наружу. До 10.08.2026 так и было:
    # семь строк «Уровень 20: …» рисовались вне красной рамки и без отступов.
    # Проверяется вложенностью, а не наличием: `has_element?("#view-gaps-list")`
    # был зелёным и тогда.
    test "списки честности лежат ВНУТРИ своих блоков", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      assert has_element?(view, "#view-gaps > #view-gaps-list"),
             "список пробелов выпал из блока `.v-gaps` — вернулся `p` вокруг `ul`?"

      assert has_element?(view, "div#view-gaps")
    end

    test "у билда с нарушениями список нарушенных уровней тоже внутри блока", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Мастер оружия требует 4 ранга Intimidate; билд без них нарушает правило
      # на каждом его уровне — ровно тот случай, ради которого блок и живёт.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 10) ++ List.duplicate(:weapon_master, 5),
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-illegal"), "фикстура перестала быть нелегальной"
      assert has_element?(view, "div#view-illegal > #view-illegal-list")
    end
  end
end
