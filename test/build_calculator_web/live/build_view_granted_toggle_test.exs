defmodule BuildCalculatorWeb.BuildViewGrantedToggleTest do
  @moduledoc """
  Переключатель автоматических (`○`) фитов на экране просмотра — задача 3.147,
  продолжение конструктора (3.146). Dan, 30.08.2026: «Давай ещё добавим эту
  галочку в просмотр билда и ещё в просмотре есть "показать текст", вот туда
  тоже можно».

  Это ПЕРЕСМОТР решения CLAUDE.md §6 от 02.08.2026 («На экране просмотра
  выданное остаётся, но обязано быть подписано»), а не его отмена — довод
  не отменяется (верен для того, кто выданное включит), меняется умолчание.
  Дефолт («выключить, чтобы разгрузить UI») — прямое слово Dan тем же днём,
  не выбор агента.

  Три вещи проверяются здесь и нигде больше:

    1. **ОДИН переключатель, а не два.** Стоит на гиде (виден сразу, не
       спрятан в диалоге «показать текст»), и его состояние двигает ОБА
       представления одного билда одним и тем же чтением
       (`BuildViewLive.export_text/1`) — клик не оставляет гид и диалог
       в разных состояниях.
    2. **Диалог — тот же `Export.text/4`, что и у конструктора**, не вторая
       копия правила: сравнивается напрямую с прямым вызовом модуля.
    3. **`vanilla` — намеренное расхождение с буквальной постановкой.**
       Постановка 3.147 (по образцу 3.146) ожидала «у ванильного билда
       переключателя нет вовсе». Но переключатель на этом экране не только
       про экспорт: гид (`guide_section/1`) печатает `○` для ОБОИХ
       ruleset'ов и печатал их так задолго до 3.145/3.146 (все 23 класса
       `vanilla/classes.json` несут `granted_feats` на 1-м уровне — тест
       3.94 «на vanilla тот же Evasion НЕ помечен» уже стоял на этом
       факте). Прятать контрол на vanilla значило бы выключать РАБОЧУЮ
       функцию гида ради несуществующей проблемы экспорта. Поэтому
       контрол гейтится не версией ruleset'а, а `has_granted?` — есть ли
       в ЭТОМ билде хоть один автоматический фит — и на vanilla он есть
       и работает для гида, оставаясь no-op для текста (тот код уже
       написан в 3.146: `vanilla`'s `leveling_guide/2` не читает
       `row.granted` вовсе).
  """
  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build
  alias BuildCalculatorWeb.Builder.{Export, Summary}

  # `render(element(view, "#view-export-text"))` includes the `<pre id="…">`
  # wrapper itself — every other test in this suite only ever substring-matches
  # against that (`=~`), never compares it whole. Byte-for-byte comparison
  # against a direct `Export.text/4` call needs the bare text, not the tag.
  defp pre_text(html) do
    html
    |> String.replace_leading(~s(<pre id="view-export-text">), "")
    |> String.replace_trailing("</pre>", "")
  end

  setup do
    ruleset = Data.ruleset!()

    # Монах 1-го уровня без единого пика — ровно фикстура из постановки
    # 3.146/3.147, где ВСЁ содержимое уровня взято из грантов, то есть самый
    # требовательный случай: если переключатель работает здесь, он работает
    # и там, где строка смешанная.
    build = Build.new(ruleset_version: ruleset.version, levels: [:monk])

    %{ruleset: ruleset, build: build, code: Encoding.encode(build)}
  end

  describe "дефолт — скрыто" do
    test "гид молчит про ○, легенда его не называет, чекбокс есть и не отмечен", %{
      conn: conn,
      code: code
    } do
      {:ok, view, html} = live(conn, ~p"/b/#{code}")

      refute html =~ "фит выдан классом"
      refute has_element?(view, "#view-guide-level-1 .pick[data-granted='1']")
      refute has_element?(view, "#view-guide-level-1-granted-cleave")

      # Положительный контроль: строка не пропала целиком — класс и номер
      # уровня остаются, просто без выдачи (та же форма, что у пустого
      # ванильного уровня в тексте, 3.146).
      assert has_element?(view, "#view-guide-level-1")
      assert render(element(view, "#view-guide-level-1")) =~ "Monk"

      assert has_element?(view, "#view-granted-checkbox")
      refute has_element?(view, "#view-granted-checkbox[checked]")
    end

    test "диалог «показать текст» и источник для копирования тоже без ○", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#show-text") |> render_click()
      dialog = render(element(view, "#view-export-text"))

      refute dialog =~ "○"
      refute dialog =~ "выдан классом"
      assert dialog =~ "01: Monk(1):"

      # `#export-source` — тот же `@export_text`, скрытый textarea для
      # «Скопировать текст»: если он не синхронен с диалогом, копия в буфер
      # обмена будет отличаться от того, что игрок только что прочитал.
      assert render(element(view, "#export-source")) =~ "01: Monk(1):"
      refute render(element(view, "#export-source")) =~ "○"
    end
  end

  describe "один клик двигает и гид, и текст одновременно" do
    test "клик по чекбоксу на гиде возвращает ○ туда, и в уже открытый диалог", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      # Диалог открыт ДО клика — синхронность должна работать в обе стороны
      # порядка действий, а не только «открыл диалог после того, как включил».
      view |> element("#show-text") |> render_click()

      view |> element("#view-granted-checkbox") |> render_click()

      assert has_element?(view, "#view-guide-level-1-granted-cleave")
      assert render(element(view, "#view-guide-level-1 .pick[data-granted='1']")) =~ "○"
      assert render(element(view, "#view-guide-legend")) =~ "фит выдан классом"

      dialog = render(element(view, "#view-export-text"))
      assert dialog =~ "○ Cleave"
      assert dialog =~ "выдан классом"

      # И обратно — тот же клик выключает оба представления снова.
      view |> element("#view-granted-checkbox") |> render_click()

      refute has_element?(view, "#view-guide-level-1-granted-cleave")
      refute render(element(view, "#view-export-text")) =~ "○"
    end

    test "чекбокс остаётся отмеченным, пока его не щёлкнут снова", %{conn: conn, code: code} do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      view |> element("#view-granted-checkbox") |> render_click()
      assert has_element?(view, "#view-granted-checkbox[checked]")

      # Закрыть и снова открыть диалог текста не должно сбрасывать выбор —
      # состояние живёт в сокете, а не в диалоге.
      view |> element("#show-text") |> render_click()
      view |> element("#text-close") |> render_click()

      assert has_element?(view, "#view-granted-checkbox[checked]")
      assert render(element(view, "#view-guide-level-1 .pick[data-granted='1']")) =~ "○"
    end
  end

  describe "диалог — тот же Export.text/4, не вторая копия" do
    test "текст в диалоге совпадает с прямым вызовом Export.text/4 в обоих состояниях", %{
      conn: conn,
      code: code,
      build: build,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")
      stats = Rules.compute(build, ruleset)
      title = Summary.title(ruleset, build, stats)

      view |> element("#show-text") |> render_click()

      hidden_dialog = render(element(view, "#view-export-text")) |> pre_text()
      hidden_direct = Export.text(build, ruleset, stats, title: title, show_granted_feats: false)
      assert hidden_dialog == hidden_direct

      view |> element("#view-granted-checkbox") |> render_click()

      shown_dialog = render(element(view, "#view-export-text")) |> pre_text()
      shown_direct = Export.text(build, ruleset, stats, title: title, show_granted_feats: true)
      assert shown_dialog == shown_direct
    end
  end

  describe "vanilla — расхождение с наивной постановкой, объяснённое в модульдоке" do
    test "чекбокс ЕСТЬ и работает для гида — vanilla-классы тоже выдают фиты", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      assert has_element?(view, "#view-granted-checkbox")
      refute has_element?(view, "#view-guide-level-1 .pick[data-granted='1']")

      view |> element("#view-granted-checkbox") |> render_click()

      assert has_element?(view, "#view-guide-level-1 .pick[data-granted='1']")
      assert render(element(view, "#view-guide-level-1")) =~ "Armor proficiency"
    end

    test "но текст не меняется — vanilla-формат никогда не нёс гранты (CLAUDE.md §3)", %{
      conn: conn
    } do
      ruleset = Data.ruleset!("vanilla")
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      view |> element("#show-text") |> render_click()
      before_click = render(element(view, "#view-export-text"))

      view |> element("#view-granted-checkbox") |> render_click()
      after_click = render(element(view, "#view-export-text"))

      assert before_click == after_click
      refute after_click =~ "Armor proficiency"
    end
  end

  describe "легенда несёт строку «взят слотом…» ровно когда @wasted? истинен" do
    # ⚠️ Задача 3.178 переместила `#view-granted-toggle` из `.v-legend`
    # в `.v-filters` и вместе с ним убрала ВСЮ машинерию 3.164 — контрол
    # больше не переносится строкой легенды, и держать его в правом углу
    # раздельным `margin-left` было незачем: `data-wasted` на самом
    # `#view-guide-legend` был заведён исключительно ради этого CSS
    # и ни для чего больше (`.v-legend[data-wasted="1"] .granted-toggle`).
    # Атрибута в разметке больше нет — эта `describe` раньше называлась
    # «data-wasted на самой легенде» и проверяла именно его; ассайн
    # `@wasted?` остался (его по-прежнему читает `:if={@wasted?}` у самой
    # строки легенды двумя строками ниже в шаблоне), так что здесь
    # осталась ровно та часть проверки, которая всё ещё о чём-то говорит —
    # что строка появляется и пропадает вместе с фактом, а не сам
    # CSS-контракт, для которого она была заведена.
    test "строка есть, когда в билде есть впустую потраченный слот", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Тот же билд, что у `Feats.wasted_text/4` в `feats_test.exs`: Ranger 9
      # выдаёт `Improved two-weapon fighting` сам, а здесь он же положен
      # в общий слот 1-го уровня — тот самый случай, который печатает
      # строку «взят слотом, но и так вышел бы даром».
      build =
        Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:ranger, 9))
        |> Build.put_feat(1, :general, :improved_two_weapon_fighting)

      {:ok, view, _html} = live(conn, ~p"/b/#{Encoding.encode(build)}")

      legend = render(element(view, "#view-guide-legend"))
      assert legend =~ "взят слотом"
    end

    test "строки нет у билда без впустую потраченного слота — положительный контроль", %{
      conn: conn,
      code: code
    } do
      {:ok, view, _html} = live(conn, ~p"/b/#{code}")

      legend = render(element(view, "#view-guide-legend"))
      refute legend =~ "взят слотом"
    end
  end
end
