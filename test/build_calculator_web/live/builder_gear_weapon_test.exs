defmodule BuildCalculatorWeb.BuilderGearWeaponTest do
  @moduledoc """
  Оружие в руках в конструкторе — задача 3.5, часть B.

  Dan назвал это основным: «в вещах чтоб можно было выбрать потом оружие и глянуть
  AB итоговый, это основное что надо». Значит проверять надо обе половины —
  что оружие можно ВЫБРАТЬ кликом и что AB после этого меняется на экране.

  ⚠️ Отдельный файл, а не дописано в `builder_live_test.exs`: тот на 200+ КБ и его
  правят соседние задачи. Форма файла взята у `builder_gear_feats_test.exs` — тот
  же блок, та же машинерия стрима и поиска.

  ⚠️ И зелёный тест здесь не то же, что работающая фича: `Phoenix.LiveViewTest`
  не применяет CSS и собирает параметры только из `phx-value-*` (HANDOFF, «восемь
  тестов кликали кнопку, сломанную в браузере»). Поэтому каждый клик здесь идёт
  через `element/2` по DOM-id, который есть в разметке, а не через `render_click`
  с придуманными параметрами.
  """

  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}

  setup do
    ruleset = Data.ruleset!("siala_41")

    # Воин 12 с «Владением клинковым» в бонусном слоте 1-го уровня: без фита
    # владения скимитар не предлагается вовсе, а это и есть предмет проверки.
    %Build{} =
      build =
      Build.new(
        ruleset_version: ruleset.version,
        race: :human,
        alignment: :true_neutral,
        levels: List.duplicate(:fighter, 12),
        base_abilities: %{str: 16, dex: 12, con: 14, int: 10, wis: 10, cha: 8},
        feats: %{1 => %{{:class_bonus, :fighter} => :siala_blade_proficiency}}
      )

    %{ruleset: ruleset, build: build}
  end

  defp open_gear(view) do
    view |> element("#gear-toggle") |> render_click()
    view
  end

  defp open_picker(view) do
    view |> open_gear() |> element("#gear-weapon-add-toggle") |> render_click()
    view
  end

  defp search(view, query) do
    view |> element("#gear-weapon-search-form") |> render_change(%{"q" => query})
    view
  end

  defp open(conn, build), do: live(conn, ~p"/?b=#{Encoding.encode(build)}")

  describe "выбор оружия" do
    test "клик по оружию кладёт его в руки и строка это показывает", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, build)

      view |> open_picker() |> search("scimitar")

      assert has_element?(view, "#gear-weapon-scimitar")
      view |> element("#gear-weapon-scimitar") |> render_click()

      assert has_element?(view, "#gear-weapon-row-scimitar")
      assert render(element(view, "#gear-weapon-row-scimitar")) =~ "Scimitar"

      # Второй клик по тому же — снимает: один обработчик на «взять» и «снять»,
      # как у фита с вещи.
      view |> element("#gear-weapon-scimitar") |> render_click()
      refute has_element?(view, "#gear-weapon-row-scimitar")
    end

    test "кнопка «снять» убирает оружие, числа остаются", %{conn: conn, build: %Build{} = build} do
      gear = Gear.new(weapon: :scimitar, weapon_attack: 5)
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)
      assert has_element?(view, "#gear-weapon-row-scimitar")

      view |> element("#gear-weapon-drop") |> render_click()

      refute has_element?(view, "#gear-weapon-row-scimitar")

      # Числа не стёрты — игрок меняет оружие, а не начинает заново.
      assert render(element(view, "#gear-weapon-attack-input")) =~ ~s(value="5")
    end
  end

  describe "список фильтруется фитами владения" do
    # 🔴 ОБЕ половины одним тестом: без фита скимитара в списке нет, с фитом есть.
    # Порознь каждая зеленела бы при неверной модели — «нет скимитара» верно и
    # у пустого списка.
    test "скимитар предлагается только с владением клинковым, посох — всегда", %{
      conn: conn,
      build: %Build{} = build,
      ruleset: ruleset
    } do
      without = %Build{build | feats: %{}}

      {:ok, no_feat, _} = open(conn, without)
      no_feat |> open_picker() |> search("s")

      # Предпосылка: фита владения в билде нет.
      assert Rules.validate_gear_weapon(without, :scimitar, ruleset) ==
               {:error, [{:requires_feat, :siala_blade_proficiency}]}

      # Скимитар в выдаче есть, но ВЫКЛЮЧЕН и назвал причину (CLAUDE.md §6 —
      # недоступное не прячем, а показываем с причиной).
      assert render(element(no_feat, "#gear-weapon-scimitar")) =~ "Владение клинковым"
      assert render(element(no_feat, "#gear-weapon-scimitar")) =~ "disabled"

      # А посох владения не требует вовсе (замер Dan) — он доступен и без фитов.
      refute render(element(no_feat, "#gear-weapon-magic_staff")) =~ "disabled"

      # Вторая половина: с фитом скимитар включён.
      {:ok, with_feat, _} = open(conn, build)
      with_feat |> open_picker() |> search("scimitar")

      refute render(element(with_feat, "#gear-weapon-scimitar")) =~ "disabled"
    end

    # Клик по выключенной строке не проходит и в обход разметки: `disabled` — это
    # браузер, а правило живёт в ядре.
    test "клик по недоступному оружию ничего не меняет", %{conn: conn, build: %Build{} = build} do
      {:ok, view, _html} = open(conn, %Build{build | feats: %{}})

      view |> open_picker() |> search("battleaxe")
      render_click(view, "pick_gear_weapon", %{"weapon" => "battleaxe"})

      refute has_element?(view, "#gear-weapon-row-battleaxe")
    end

    # ⚠️ Оговорка читается ДО клика, а не в панели пробелов после него: про дубину
    # никто не написал, требует ли она владения, и знать это надо до выбора.
    # ✅ Оговорка снята наблюдением Dan 16.08.2026: дубина владения не требует,
    # и «не сказано ни на одной вики» стало неправдой. ⚠️ Предлагаться она
    # обязана по-прежнему — проверяется именно это, а не отсутствие строки:
    # исчезнуть вместе с оговоркой она не должна.
    test "дубина предлагается и больше ни о чём не оговаривается", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, build)
      view |> open_picker() |> search("club")

      html = render(element(view, "#gear-weapon-club"))

      refute html =~ "disabled"
      refute html =~ "не сказано ни на одной вики"
    end
  end

  describe "числа оружия доезжают до AB" do
    # 🔴 Главное требование Dan: «выбрать оружие и глянуть AB итоговый».
    test "усиление атаки поднимает AB на экране", %{conn: conn, build: %Build{} = build} do
      {:ok, view, _html} = open(conn, build)
      open_gear(view)

      before = render(element(view, "#stat-attack_bonus"))

      # ⚠️ Задача 3.134: число уехало из `#gear-form` в свою форму рядом
      # с самим оружием (`#gear-weapon-attack-form`), тем же приёмом, что
      # уже был у навыков с вещи — `phx-change="gear_weapon_attack"` читает
      # РОВНО `params["attack"]`, без вложенного ключа `weapon`.
      view
      |> element("#gear-weapon-attack-form")
      |> render_change(%{"attack" => "5"})

      # Пока оружия в руках нет, число ни во что не идёт — это не «поле не
      # работает», а честное состояние: бонус принадлежит предмету.
      assert render(element(view, "#stat-attack_bonus")) == before

      view |> element("#gear-weapon-add-toggle") |> render_click()
      view |> search("scimitar") |> element("#gear-weapon-scimitar") |> render_click()

      # Теперь предмет в руках — и AB вырос ровно на 5: BAB 12 + STR +3 = 15,
      # плюс 5 атаки. ⚠️ Было +8 (5 атаки и 3 усиления), пока у предмета было
      # второе число; задача 3.52 оставила одно.
      assert before =~ "AB +15"
      assert render(element(view, "#stat-attack_bonus")) =~ "AB +20"
    end

    # Разбор AB называет оружие по имени — это вторая половина запроса Dan
    # («будем показывать в деталях об АБ значение с конкретным оружием»).
    test "поп-ап разбора AB называет оружие и его число", %{conn: conn, build: %Build{} = build} do
      gear = Gear.new(weapon: :scimitar, weapon_attack: 5)
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      # ⚠️ Термы поп-апа едут в `data-pop-terms` как JSON (хук рисует их на
      # клиенте), поэтому проверяется имя И его число рядом, а не готовая строка:
      # `=~ "Scimitar"` зеленело бы и у разбора, потерявшего число.
      html = render(element(view, "#stat-attack_bonus"))

      assert html =~ "Scimitar&quot;,&quot;value&quot;:&quot;+5"

      # ⚠️ И второго терма про оружие нет вовсе: до задачи 3.52 рядом стоял
      # «Scimitar (усиление)», и подпись с суффиксом появляется теперь только
      # у предмета с несколькими числами — а он объявлен одним.
      refute html =~ "Scimitar ("
    end
  end

  # 🔴 Задача 3.134 переехала числа оружия из общей `#gear-form` в свои формы,
  # рядом с самим оружием, — ровно та ловушка, которую называет постановка:
  # у КАЖДОЙ формы есть только СВОИ поля, и `handle_event/3` каждой из них
  # обязан переписывать только своё. До правки `"gear"` читал `params["weapon"]`
  # прямо из общего набора; если бы вынос числа в свою форму не сопровождался
  # разводом обработчиков, любая правка характеристики стирала бы AB оружия
  # молча (`params["weapon"]` отсутствует в этой форме → `%{}` →
  # `gear_number(nil)` → 0), и наоборот.
  describe "формы не стирают чужое (задача 3.134)" do
    test "правка характеристики в #gear-form не стирает AB обеих рук", %{
      conn: conn,
      build: %Build{} = build
    } do
      # ⚠️ Оба числа кодируются в ссылку ТОЛЬКО вместе со своим оружием
      # (`Encoding.weapon_entries/1`/`off_weapon_entries/1`: «нулевое число
      # пишется, а вот отсутствие оружия — нет») — `open/2` в этом файле
      # всегда гоняет билд через ссылку, поэтому здесь у обеих рук названо
      # оружие, а не только число.
      gear =
        Gear.new(
          weapon: :scimitar,
          weapon_attack: 5,
          off_hand_weapon: :mace,
          off_hand_weapon_attack: 3
        )

      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)

      view
      |> element("#gear-form")
      |> render_change(%{"ability" => %{"str" => "4"}})

      assert render(element(view, "#gear-weapon-attack-input")) =~ ~s(value="5")
      assert render(element(view, "#gear-off-weapon-attack-input")) =~ ~s(value="3")
    end

    # Обратная сторона той же ошибки: правка AB не имеет полей характеристик,
    # AC, надетого или сейвов в своей форме, значит не может их стереть —
    # но только если `"gear_weapon_attack"` не переписывает ничего, кроме
    # `weapon_attack`.
    test "правка AB главной руки не стирает характеристики #gear-form", %{
      conn: conn,
      build: %Build{} = build
    } do
      gear = Gear.new(abilities: %{str: 4}, saves: 2, worn: %{armor: :full_plate})
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)

      view
      |> element("#gear-weapon-attack-form")
      |> render_change(%{"attack" => "5"})

      assert render(element(view, "#gear-ability-input-str")) =~ ~s(value="4")
      assert render(element(view, "#gear-saves-input")) =~ ~s(value="2")
      assert has_element?(view, "#gear-worn-armor[data-filled='1']")
    end
  end

  describe "оружие, потерявшее основание" do
    # 🔴 Требование задания: помечать, а не молча выбрасывать. Ссылка с оружием и
    # без фита владения открывается, оружие в строке ЕСТЬ, и рядом с ним причина.
    test "оружие без фита владения названо с причиной, а не исчезло", %{
      conn: conn,
      build: %Build{} = build
    } do
      gear = Gear.new(weapon: :scimitar, weapon_attack: 5)
      {:ok, view, _html} = open(conn, %Build{build | feats: %{}, gear: gear})

      open_gear(view)

      assert has_element?(view, "#gear-weapon-row-scimitar")
      assert render(element(view, "#gear-weapon-bad")) =~ "Владение клинковым"

      # И в числа оно не идёт: AB тот же, что без оружия (BAB 12 + STR +3).
      assert render(element(view, "#stat-attack_bonus")) =~ "AB +15"
    end

    # Положительный контроль: у законного оружия строки с причиной нет вовсе.
    test "законное оружие причины не показывает", %{conn: conn, build: %Build{} = build} do
      gear = Gear.new(weapon: :scimitar, weapon_attack: 5)
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)

      assert has_element?(view, "#gear-weapon-row-scimitar")
      refute has_element?(view, "#gear-weapon-bad")
    end
  end

  describe "ссылка" do
    test "оружие и его число переживают шаринг", %{conn: conn, build: %Build{} = build} do
      gear = Gear.new(weapon: :scimitar, weapon_attack: 5)
      code = Encoding.encode(%Build{build | gear: gear})

      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")
      open_gear(view)

      assert has_element?(view, "#gear-weapon-row-scimitar")
      assert render(element(view, "#gear-weapon-attack-input")) =~ ~s(value="5")

      # ⚠️ Поля усиления в форме больше нет вовсе (задача 3.52) — не «оно пустое»,
      # а его нет: иначе игрок вводил бы число, которого билд не несёт.
      refute has_element?(view, "#gear-weapon-enhancement-input")
    end

    test "«Сбросить вещи» убирает и оружие", %{conn: conn, build: %Build{} = build} do
      gear = Gear.new(weapon: :scimitar, weapon_attack: 5)
      {:ok, view, _html} = open(conn, %Build{build | gear: gear})

      open_gear(view)
      view |> element("#gear-clear") |> render_click()

      refute has_element?(view, "#gear-weapon-row-scimitar")
    end
  end

  # Задача дизайнера 16.08.2026: жалоба Dan — «требование фита выглядит
  # громоздко и не всегда помещается». Три вещи закреплены отдельно, потому
  # что каждая могла бы сломаться порознь, не задев остальные.
  describe "причина отказа — вёрстка (жалоба Dan 16.08.2026)" do
    # `🔒` — переиспользование готового языка карточек класса (`card-lock`),
    # а не изобретение нового: то же «недоступно, вот почему» уже читается
    # с этим глифом там. Без него список читался бы прозой, что и было жалобой.
    test "причина несёт замок — тот же язык, что у карточек класса", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, %Build{build | feats: %{}})
      view |> open_picker() |> search("battleaxe")

      assert render(element(view, "#gear-weapon-battleaxe")) =~ "🔒"
    end

    # Список без поиска — весь справочник, но недоступное всё равно НЕ
    # прячем (CLAUDE.md §6): без фитов владения из 41 оружия доступны только
    # три, у остальных 38 причина — одно из пяти повторяющихся предложений
    # («нужен фит Владение топорами» и т.п.). Разброс по алфавиту читался как
    # рваная проза; правка группирует одинаковые причины подряд, НЕ трогая,
    # какие именно 24 из 41 попадают в срез (это отдельный тест ниже).
    test "без поиска одинаковые причины отказа стоят подряд, а не вразнобой", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, %Build{build | feats: %{}})
      open_picker(view)

      document = view |> render() |> LazyHTML.from_fragment()
      rows = LazyHTML.query(document, "#gear-weapon-options .gear-pick")

      # `LazyHTML.text/1` отдаёт строку для одного узла, а не список для
      # коллекции — `Enum.map/2`, как в её собственном примере в docstring.
      reasons =
        rows
        |> LazyHTML.query(".feat-why")
        |> Enum.map(&LazyHTML.text/1)

      # `chunk_by` схлопывает подряд идущие повторы. Если группировка
      # работает, различных «пробегов» ровно столько же, сколько различных
      # причин — то есть каждая причина встречается ОДНИМ непрерывным блоком.
      # Если бы список остался вразнобой по имени, пробегов было бы больше
      # (одна и та же причина встречалась бы несколькими разрозненными
      # кусками), и это равенство не выполнялось бы.
      assert length(Enum.chunk_by(reasons, & &1)) == length(Enum.uniq(reasons))
    end

    # ⚠️ Ловушка, на которой сломалась первая версия этой правки: сортировка
    # ОТБОРА (а не только показа) по причине меняла, какие 24 из 41 видны без
    # поиска, и ровно Battleaxe/Greataxe/Dart — то, что было на скриншоте
    # жалобы, — выпадали из среза. Группировка обязана трогать только ПОРЯДОК
    # показа уже отобранных строк, а не сам отбор.
    test "группировка не меняет, какое оружие видно без поиска", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, %Build{build | feats: %{}})
      open_picker(view)

      assert has_element?(view, "#gear-weapon-battleaxe")
      assert has_element?(view, "#gear-weapon-greataxe")
      assert has_element?(view, "#gear-weapon-dart")
    end

    # ⚠️ Самая вероятная ловушка задачи (по словам самого задания): при
    # активном поиске группировка ОБЯЗАНА молчать, а порядок — оставаться
    # строго по релевантности. «axe» специально задевает ДВЕ разных причины
    # («древковым» у Double axe, «топорами» у остальных четырёх) с разными
    # очками нечёткого поиска — если бы группировка вмешалась, Handaxe (лучший
    # счёт среди «топорами») не оказался бы первым в своей группе, это место
    # заняла бы алфавитно первая Battleaxe.
    test "при активном поиске порядок остаётся по релевантности, не по причине", %{
      conn: conn,
      build: %Build{} = build
    } do
      {:ok, view, _html} = open(conn, %Build{build | feats: %{}})
      view |> open_picker() |> search("axe")

      document = view |> render() |> LazyHTML.from_fragment()

      ids =
        document
        |> LazyHTML.query("#gear-weapon-options .gear-pick")
        |> LazyHTML.attribute("id")

      assert ids == ~w(
               gear-weapon-double_axe
               gear-weapon-throwing_axe
               gear-weapon-handaxe
               gear-weapon-greataxe
               gear-weapon-battleaxe
               gear-weapon-dwarven_waraxe
             )
    end
  end
end
