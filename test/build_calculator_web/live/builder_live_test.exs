defmodule BuildCalculatorWeb.BuilderLiveTest do
  @moduledoc """
  The builder's key journeys, driven through the DOM ids the templates carry.

  Assertions go through `element/2` and `has_element?/2` rather than raw HTML
  (AGENTS.md, CLAUDE.md §7): the markup will keep moving, the ids are the
  contract.
  """
  use BuildCalculatorWeb.ConnCase

  import Phoenix.LiveViewTest

  alias BuildCalculator.Data
  alias BuildCalculator.Encoding
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear, Spells}
  alias BuildCalculatorWeb.Builder.{Feats, Gaps}

  # A level 41 Fighter with a flat CON of 10: max hit die every level, so hit
  # points are 41 × 10 = 410 before any equipment. That makes the cascade below
  # arithmetic anybody can check by hand.
  defp fighter_41(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:fighter, 41),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
    )
  end

  # `fighter_41/1`, обрезанный до 35 уровней, но с ЗАКРЫТЫМ созданием
  # персонажа (задача 3.69). Без расы и мировоззрения `level_ceiling/2`
  # держит `active` на уже взятом 35-м уровне, а не пускает на новый,
  # 36-й — а именно позицию НА 36-м и проверяет весь блок ниже. Раса
  # и мировоззрение — не предмет этих тестов; human выбран так же, как
  # и в `fighter_41/1`, — за отсутствие модификаторов характеристик,
  # чтобы не задеть арифметику HP/BAB, которую блок и проверяет. 35 < 40,
  # так что расовый бонус Сиалы (считается только на 40–41-м, CLAUDE.md §3)
  # здесь неоткуда взяться — раса ничего не прибавляет к числам блока.
  defp fighter_36_of_41(ruleset) do
    %Build{} = build = fighter_41(ruleset)
    %Build{build | race: :human, alignment: :lawful_good} |> Build.truncate(35)
  end

  # Задача 3.45: `Diamond soul` — единственная выдача класса на этом уровне
  # монаха («monk 12» в `granted_feats`), и ровно на 12-м Dan решил показывать
  # строку SR панели итогов (`Summary.spell_resistance_visible?/1`).
  defp monk_up_to(ruleset, levels) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:monk, levels),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
    )
  end

  # Задача 3.59B: монах 5, WIS 18 (мод +4). AC голым 15 = 10 база + 4 мудрости
  # (`Monk AC bonus`, на Сиале сдвинут с 1-го уровня на 4-й) + 1 колонка
  # таблицы класса (за каждые 5 уровней МОНАХА — сама постановка 3.55/3.59
  # называет ровно эти числа для монаха 5 с WIS 14; здесь WIS 18, чтобы дать
  # фиту круглый модификатор). Числа сверены прогоном `Rules.compute/2` перед
  # тем, как лечь в тест — не выдуманы.
  defp monk_5_wis_18(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:monk, 5),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 18, cha: 10}
    )
  end

  # Воин БЕЗ единого уровня монаха, с 5 базовыми рангами Кувырка (кросс-
  # классовый — куплен по одному рангу на нечётных уровнях 1/3/5/7/9, под
  # потолком `(уровень + 3) / 2` на каждом из них). Единственная собственная
  # прибавка к AC — Tumble +1 (`per_skill_ranks`, +1 за каждые 5 рангов):
  # билд нарочно без монаха, чтобы «+1 своих» не могло случайно совпасть
  # с монашеской арифметикой и спрятать баг, который и завёл задачу 3.59B.
  defp fighter_with_tumble(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:fighter, 9),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{
        1 => %{tumble: 1},
        3 => %{tumble: 1},
        5 => %{tumble: 1},
        7 => %{tumble: 1},
        9 => %{tumble: 1}
      }
    )
  end

  # То же, что `monk_5_wis_18/1`, растянутое до 9 уровней и с теми же 5
  # рангами Кувырка, что и `fighter_with_tumble/1` — три собственных терма
  # AC разом (`Monk AC bonus`, колонка класса, Tumble), билд гол (ничего
  # не надето), ради положительного контроля на задачу 3.59B: строка
  # каскада обязана различать все три источника, а не молчаливо слить их
  # в одно число или спутать одноимённую арифметику («+1 за каждые 5» у обоих).
  defp monk_with_tumble(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:monk, 9),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 18, cha: 10},
      skills: %{
        1 => %{tumble: 1},
        3 => %{tumble: 1},
        5 => %{tumble: 1},
        7 => %{tumble: 1},
        9 => %{tumble: 1}
      }
    )
  end

  # Престиж-уровни с прибавкой к характеристике на них: уровень 12 берётся
  # Чемпионом Торма (престиж), а прибавка на 12-м уходит в STR — то есть на
  # одной строке лестницы сходятся цвет класса и оттенок характеристики,
  # и именно на этой паре ловится подмена `--cls-s`/`--cls-l` поддереву.
  defp fighter_then_champion_of_torm(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:fighter, 7) ++ List.duplicate(:champion_of_torm, 10),
      base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 10},
      ability_increases: %{4 => :str, 8 => :str, 12 => :str, 16 => :str}
    )
  end

  # Шапка `#level-0` красится классом ПЕРВОГО уровня, поэтому престиж туда
  # доезжает только так — билдом, который начинается престиж-классом. Что он
  # нелегален по требованиям, для разметки шапки безразлично.
  defp champion_of_torm_first(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:champion_of_torm, 3),
      base_abilities: %{str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 10}
    )
  end

  # Чистый заклинатель, вложивший всё в Spellcraft: +1 ко всем трём сейвам
  # за каждые 5 рангов — прибавка, которую игроки не считают (CLAUDE.md §3).
  defp spellcraft_sorcerer(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:sorcerer, 40),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 16},
      skills: Map.new(1..40, &{&1, %{spellcraft: if(&1 == 1, do: 4, else: 1)}})
    )
  end

  # ⚠️ Дословный билд Дана (наблюдение в игре 03.08.2026): соркерер 1–39, 40-м
  # уровнем воин, 35 рангов Spellcraft залиты по одному на уровнях соркерера —
  # каждый под потолком своего уровня, так что билд законен целиком.
  defp sorcerer_then_fighter(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:sorcerer, 39) ++ [:fighter],
      base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 16},
      skills: Map.new(1..35, &{&1, %{spellcraft: 1}})
    )
  end

  # Дословный повод Dan 03.08.2026 (AGENT_QUEUE §3.4b): «тёмный эльф-клирик
  # может залить много эпической мудрости, большой мод мудрости даст много
  # спота». Spot не входит в классовые навыки клирика (кросс-классовый билду
  # целиком), поэтому куплен всего один ранг — под потолком кросс-класса
  # первого уровня, `(1 + 3) / 2 = 2`, и этого достаточно, чтобы показать
  # вклад характеристики и расы в разборе.
  defp elf_cleric_with_spot(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :elf,
      levels: List.duplicate(:cleric, 5),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 20, cha: 10},
      skills: %{1 => %{spot: 1}}
    )
  end

  # Та же идея, но WIS НЕЧЁТНЫЙ (19, не 20): +1 к характеристике на чётном
  # билде не двигает МОДИФИКАТОР (`div(20 - 10, 2) == div(21 - 10, 2) == 5`),
  # а без сдвига модификатора нечего показать призраком. Уровней ровно 4 —
  # прибавка к характеристике даётся на 4-м уровне ПЕРСОНАЖА, и билд обязан
  # реально в него упереться, а не просто существовать где-то дальше.
  defp elf_cleric_odd_wis(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      race: :elf,
      levels: List.duplicate(:cleric, 4),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 19, cha: 10},
      skills: %{1 => %{spot: 1}}
    )
  end

  # Bardic Knowledge Арфиста (`siala_41/skills.json`, `class_level_bonuses`):
  # бонус к Lore РАВЕН уровню класса Арфиста, начиная со 2-го. Наведение на
  # класс — это НЕ только «сменится цена/потолок навыка» (то живёт в секции
  # «Навыки» сцены и требует уже выбранного класса уровня, см. AGENT_QUEUE
  # §7), а иногда и прямой сдвиг ЗНАЧЕНИЯ через классовую способность: два
  # уровня Арфиста уже дают Lore +2, третий поднимет её к +3.
  defp harper_lore_build(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      # Задача 3.69: без расы и мировоззрения ссылка открылась бы на уже
      # взятом 2-м уровне вместо нового 3-го — три теста ниже наводятся
      # именно на предстоящий, ещё пустой уровень (`level_ceiling/2`).
      race: :human,
      alignment: :lawful_good,
      levels: List.duplicate(:harper_scout, 2),
      base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{1 => %{lore: 1}}
    )
  end

  # Вор, вложившийся в Hide — навык с `armor_check_penalty: :applies` (штраф от
  # брони) — и взявший на него `Skill focus`: фит с прибавкой, но без
  # проверяемого числа (навык выбирается, величина есть только прозой на
  # Fandom), поэтому попадает в `unmodelled_feats`.
  defp rogue_with_hide_and_skill_focus(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:rogue, 5),
      base_abilities: %{str: 10, dex: 16, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{1 => %{hide: 4}},
      feats: %{1 => %{general: {:skill_focus, :hide}}}
    )
  end

  # ⚠️ Второй фикстур с фитом на навык — и он про ПРОТИВОПОЛОЖНОЕ (задача 3.92).
  # У соседа сверху `Skill focus` теперь СЧИТАЕТСЯ (+3), а `Favored enemy`
  # по-прежнему нет: его прибавка действует только против выбранного типа
  # существ (fandom "Favored enemy" revid 63601). Панель обязана уметь оба
  # разговора, поэтому фикстура два, а не один с флагом.
  defp ranger_with_spot_and_favored_enemy(ruleset) do
    Build.new(
      ruleset_version: ruleset.version,
      levels: List.duplicate(:ranger, 5),
      base_abilities: %{str: 10, dex: 16, con: 10, int: 10, wis: 10, cha: 10},
      skills: %{1 => %{spot: 4}},
      feats: %{1 => %{{:class_bonus, :ranger} => {:favored_enemy, :goblinoid}}}
    )
  end

  # Задача 3.60: воин 1..`top` со ВСЕМИ слотами фитов и прибавками к
  # характеристике заполненными, КРОМЕ уровней, названных в `skip_feats`/
  # `skip_increases`, — намеренные пропуски, ровно сценарий Dan («пропустил
  # на 20 лвл фит. Сам уже на 35 уровне»). Значение фита не важно и не обязано
  # быть легальным по пререквизитам: `ladder_slots/3` (её и читает
  # `first_gap/2`) смотрит только «слот пуст или нет», а не прошёл ли пик
  # требования — тем же приёмом уже собран `weapon_master_ladder_build/1`
  # выше в этом файле.
  defp fighter_with_gaps(ruleset, top, opts) do
    skip_feats = Keyword.get(opts, :skip_feats, [])
    skip_increases = Keyword.get(opts, :skip_increases, [])

    shell =
      Build.new(
        ruleset_version: ruleset.version,
        # Задача 3.69: без расы и мировоззрения `load_code/3` останавливает
        # `active` на уже взятом `top`-м уровне, а не на следующем, новом —
        # и тест ниже, который сперва идёт на `top` кликом, теряет патч
        # (там уже нечего двигать). Гонка за пропусками не про создание
        # персонажа, поэтому оба закрыты в самой фикстуре.
        race: :human,
        alignment: :lawful_good,
        levels: List.duplicate(:fighter, top),
        # ⚠️ 16, а не 10: один из тестов ниже закрывает оставшийся пропуск
        # НАСТОЯЩИМ кликом по фиту из списка, а не значением, зашитым в билд
        # напрямую, — и туда Power Attack обязан попасть легальным (нужен
        # STR 13). Остальные слоты фит «не смотрит» на легальность вовсе
        # (`ladder_slots/3` читает только «пусто или нет»), так что высокие
        # статы им не мешают и не помогают.
        base_abilities: %{str: 16, dex: 16, con: 16, int: 16, wis: 16, cha: 16}
      )

    feats =
      for level <- 1..top,
          level not in skip_feats,
          slot <- BuildCalculator.Rules.FeatSlots.at(shell, ruleset, level),
          reduce: %{} do
        acc ->
          Map.update(
            acc,
            level,
            %{slot.id => :power_attack},
            &Map.put(&1, slot.id, :power_attack)
          )
      end

    increases =
      ruleset.epic.ability_increase_levels
      |> Enum.filter(&(&1 <= top and &1 not in skip_increases))
      |> Map.new(&{&1, :str})

    %Build{shell | feats: feats, ability_increases: increases}
  end

  setup do
    %{ruleset: Data.ruleset!()}
  end

  # `Summary.ability_summary/2`'s breakdown travels as JSON in `data-pop-terms`
  # (задача 3.13) — inert plumbing for the `.StatPop` hook, not printed text.
  # `LazyHTML.attribute/2` reads the real, already-unescaped attribute value
  # (Phoenix HTML-escapes `"` to `&quot;` on the way out; this undoes that),
  # so a test can assert on the *decoded* terms instead of guessing how the
  # server happened to escape the JSON string.
  defp pop_terms(html, dom_id) do
    [raw] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("##{dom_id} .stat-pop-trigger")
      |> LazyHTML.attribute("data-pop-terms")

    Jason.decode!(raw)
  end

  # Задача 3.88: секция гэпов ДАННЫХ (не гэпов этого билда) гейтится
  # `@gaps.data_real_count > 0`, а живые данные сегодня дают 0 (задача 3.86)
  # — единственный честный способ проверить, что ворота ОТКРЫВАЮТСЯ, это
  # синтетический ruleset с наведённой дырой, а не надежда, что живые данные
  # когда-нибудь снова станут ненулевыми (постановка задачи предупреждает
  # ровно об этой ловушке). Rulesets are compiled in
  # (`BuildCalculator.Data`, «compiled into the beam»): реальный `live/2` не
  # может подхватить ad-hoc ruleset по строке версии, которой нет в
  # `Data.versions/0`. Вместо этого шаблон (`BuilderLive.render/1`,
  # авто-сгенерированная функция co-located `.html.heex`) вызывается
  # напрямую с одним-двумя переопределёнными assign'ами; остальные — из
  # ДЕЙСТВИТЕЛЬНО смонтированной, рабочей страницы.
  #
  # ⚠️ `:sys.get_state/1` — не догадка: `AGENTS.md` уже разрешает этот
  # приём для LiveView-тестов (там — для синхронизации, здесь — чтобы
  # прочитать `%Phoenix.LiveView.Socket{}` из состояния тестового прокси-
  # процесса, `state.socket.assigns`). `Phoenix.LiveViewTest.rendered_to_string/1`
  # — публичная, документированная функция, а не обход API.
  defp render_assigns(view, overrides) do
    %{socket: %{assigns: assigns}} = :sys.get_state(view.pid)

    assigns
    |> Map.merge(overrides)
    |> BuildCalculatorWeb.BuilderLive.render()
    |> rendered_to_string()
  end

  describe "shell" do
    test "renders the three columns, the ladder and the totals panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#builder-cols")
      assert has_element?(view, "#level-ladder")
      assert has_element?(view, "#stage")
      assert has_element?(view, "#totals-panel")
      assert has_element?(view, "#stat-hp")
      assert has_element?(view, "#share-link")
    end

    test "the ladder runs from the creation step to the level cap", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#level-0")
      assert has_element?(view, "#level-1")
      assert has_element?(view, "#level-#{ruleset.level_cap}")
      refute has_element?(view, "#level-#{ruleset.level_cap + 1}")
      assert has_element?(view, "#epic-divider")
    end

    # ⚠️ Задача 3.49 (18.08.2026): было «не полностью» — тот самый заголовок,
    # который считал решённые споры источников и процитированные константы
    # дырами наравне с настоящими. Подпись сменилась на «ещё не в расчёте»,
    # и число за ней теперь `data_real_count`, а не общая длина `ruleset.gaps`.
    #
    # 🔴 Задача 3.88 (24.08.2026, решение Dan) — ПЕРЕСМОТР: «данную секцию
    # с сайта уже убрал бы… для пользователей я предлагаю дыры больше не
    # показывать»; «согласен, прячем до момента появления дыр». Раньше
    # (задача 3.86, тот же день, что список настоящих дыр опустел) у
    # пометки было две ветки — при `data_real_count == 0` она печатала
    # «числа не окончательные» без счётчика вместо молчания. Обе ветки
    # ушли: пометка ПРЯЧЕТСЯ целиком, пока настоящих дыр нет, и это ворота,
    # а не удаление — `Gaps.summary/3` не тронут, тест ниже это доказывает.
    test "the standing notice is gone while there is no real data gap", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      build = Build.new(ruleset_version: ruleset.version)
      summary = Gaps.summary(ruleset, build, Rules.compute(build, ruleset))

      # Положительный контроль на саму посылку теста (задача 3.86): если
      # реальная дыра когда-нибудь вернётся в данные, этот ассерт первым
      # скажет, что тест для сегодняшнего состояния больше не годится —
      # раньше, чем `refute` ниже просто перестанет что-то ловить.
      assert summary.data_real_count == 0

      refute has_element?(view, "#builder-notice")
    end

    # ⚠️ Главный тест ворот, который требует постановка задачи: на
    # СИНТЕТИЧЕСКОМ ruleset'е с наведённой дырой, а не на живых данных —
    # живые сегодня дают ноль, и тест на них молча перестал бы что-либо
    # проверять, если бы условие сломалось в положение «всегда закрыто».
    # `render_assigns/2` рендерит шаблон `BuilderLive.render/1` напрямую
    # с одним переопределённым assign'ом — см. её докстроку про то, почему
    # обычный `live/2` с другой версией ruleset'а здесь не годится.
    test "the standing notice returns on its own once a real data gap exists", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      synthetic_ruleset = %{ruleset | gaps: [induced | ruleset.gaps]}
      build = Build.new(ruleset_version: ruleset.version)

      synthetic_gaps =
        Gaps.summary(synthetic_ruleset, build, Rules.compute(build, synthetic_ruleset))

      assert synthetic_gaps.data_real_count > 0

      html = render_assigns(view, %{gaps: synthetic_gaps})

      assert html =~ ~s(id="builder-notice")

      assert html =~
               "Часть правил Сиалы ещё не в расчёте — #{synthetic_gaps.data_real_count} пробелов в данных."

      assert html =~ "Числа не окончательные."
    end
  end

  # Задача 3.17: раньше «раса, мировоззрение, статы» были отдельным нулевым
  # экраном; теперь это первые три секции ЕДИНОГО редактора уровня 1, и все
  # четыре теста ниже по-прежнему проходят без единого клика по лестнице —
  # `live(conn, ~p"/")` уже открывает уровень 1 (`mount/3`, `active: 1`).
  describe "раса, мировоззрение и статы — часть единого редактора уровня 1" do
    test "picking a race marks the card and shows the Siala name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()

      # ⚠️ Задача 3.18: здесь стоял клик по `#section-race-toggle` — секция
      # сворачивалась сама, и её приходилось раскрывать обратно, чтобы
      # добраться до карточек. Больше не сворачивается (`section_pending?/2`),
      # так что клик не нужен: карточки на месте сразу.
      assert has_element?(view, "#race-card-dwarf[data-chosen='1']")
      # Гном is Dwarf, Карлик is Gnome — the collision CLAUDE.md §4 insists on.
      assert render(element(view, "#race-card-dwarf")) =~ "Гном"
      assert render(element(view, "#race-card-gnome")) =~ "Карлик"
    end

    test "point buy spends and refunds its budget", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      before = render(element(view, "#point-buy-budget"))
      view |> element("#point-buy-str-up") |> render_click()
      spent = render(element(view, "#point-buy-budget"))

      refute before == spent

      view |> element("#point-buy-str-down") |> render_click()
      assert render(element(view, "#point-buy-budget")) == before
    end

    test "the floor cannot be lowered further", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#point-buy-str-down[disabled]")
    end

    # Задача 3.156 (Dan, 01.09.2026): двое живых игроков читали число в
    # степпере как ПОКУПКУ и путали свою характеристику — в игре там стоит
    # итог. Половина каскада уже проверена вычетом (кастерский пол выше в
    # файле, раса даёт −2); здесь — прибавка: Могучий человек (Half-Orc)
    # даёт STR +2, и это положительный контроль на ту же строку.
    test "раса с положительным модификатором: покупка 14 показана как 16", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-half_orc") |> render_click()

      # От пола (8) до покупки 14 — шесть кликов, бюджета (30) хватает
      # с большим запасом (шесть очков), класс первого уровня ещё не
      # выбран, так что кастерский пол в игру не вступает.
      view |> element("#point-buy-str-up") |> render_click()
      view |> element("#point-buy-str-up") |> render_click()
      view |> element("#point-buy-str-up") |> render_click()
      view |> element("#point-buy-str-up") |> render_click()
      view |> element("#point-buy-str-up") |> render_click()
      view |> element("#point-buy-str-up") |> render_click()

      assert render(element(view, "#point-buy-str .val")) =~ "16"
      refute render(element(view, "#point-buy-str .val")) =~ "14"
    end

    test "alignment is chosen from the nine", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#alignment-lawful_good") |> render_click()

      # Та же секция, что и у расы выше, и та же правка задачи 3.18: сама
      # больше не сворачивается, раскрывать обратно нечего.
      assert has_element?(view, "#alignment-lawful_good[data-chosen='1']")
    end
  end

  # Задача 3.18 (наблюдение Dan 05.08.2026: «экран дёргается, элементы слегка
  # ездят», «зачастую хочется изменить выбор, а секция уже скрыта»).
  #
  # ⚠️ Это ПЕРЕСМОТР осознанного решения, а не починка недосмотра: CLAUDE.md
  # §6 требовал «готовое схлопывается в строку-сводку». Довод не отменён —
  # он проиграл второму, «правка сделанного выбора должна оставаться дешёвой».
  # Замеры, из которых это следует, — в `BuilderLive.section_pending?/2`.
  #
  # Раздел держит обе половины нового договора: секция не сворачивается сама,
  # а `data-pending` остался тем же самым вопросом («висит ли здесь решение»)
  # в новой роли — цели, к которой хук `.FocusPending` подвозит экран.
  describe "секция не сворачивается сама (задача 3.18)" do
    test "выбранная раса остаётся на экране — передумать можно без клика по шапке", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#section-race[data-pending='1']")

      view |> element("#race-card-dwarf") |> render_click()

      # Тело секции на месте, значит и все карточки: вот она, дешёвая правка.
      assert has_element?(view, "#section-race-body")
      assert has_element?(view, "#race-card-dwarf[data-chosen='1']")
      assert has_element?(view, "#race-card-human")

      # Положительный контроль: решение снято именно с этой секции, а не
      # со всех сразу — мировоззрение всё ещё ждёт.
      assert has_element?(view, "#section-race[data-pending='0']")
      assert has_element?(view, "#section-alignment[data-pending='1']")

      # И передумать действительно можно одним кликом, без открывания.
      view |> element("#race-card-human") |> render_click()
      assert has_element?(view, "#race-card-human[data-chosen='1']")
      refute has_element?(view, "#race-card-dwarf[data-chosen='1']")
    end

    test "выбранное мировоззрение остаётся на экране", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#alignment-lawful_good") |> render_click()

      assert has_element?(view, "#section-alignment-body")
      assert has_element?(view, "#section-alignment[data-pending='0']")

      view |> element("#alignment-chaotic_evil") |> render_click()
      assert has_element?(view, "#alignment-chaotic_evil[data-chosen='1']")
    end

    test "выбранный класс уровня остаётся на экране — самая дорогая секция и самый нужный возврат",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#section-class-body")
      assert has_element?(view, "#class-card-fighter[data-chosen='1']")
      assert has_element?(view, "#section-class[data-pending='0']")

      # Сменить класс уровня — один клик, без раскрывания.
      view |> element("#class-card-rogue") |> render_click()
      assert has_element?(view, "#class-card-rogue[data-chosen='1']")
    end

    test "выбранная прибавка к характеристике остаётся на экране", %{conn: conn, ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:fighter, 4))
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#level-4") |> render_click()
      assert has_element?(view, "#section-increase[data-pending='1']")

      view |> element("#increase-card-str") |> render_click()

      assert has_element?(view, "#section-increase-body")
      assert has_element?(view, "#increase-card-str[data-chosen='1']")
      assert has_element?(view, "#section-increase[data-pending='0']")
    end

    test "свернуть секцию может только игрок — и она остаётся свёрнутой", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#section-race-body")

      # Первый клик по шапке теперь ЗАКРЫВАЕТ (до 3.18 у уже свёрнутой самой
      # собой секции он открывал), второй — открывает обратно.
      view |> element("#section-race-toggle") |> render_click()
      refute has_element?(view, "#section-race-body")

      # ⚠️ Положительный контроль к `refute` выше: секция не исчезла, а
      # свернулась, и шапка по-прежнему называет состояние («никогда не
      # прятать state», `BuilderComponents.section/1`).
      assert has_element?(view, "#section-race")
      assert has_element?(view, "#section-race-toggle[data-open='0']")
      assert has_element?(view, "#section-race[data-pending='1']")

      view |> element("#section-race-toggle") |> render_click()
      assert has_element?(view, "#section-race-body")
    end

    test "свёрнутая игроком секция всё равно называет несделанное в шапке", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#section-alignment-toggle") |> render_click()

      refute has_element?(view, "#section-alignment-body")
      assert render(element(view, "#section-alignment-toggle")) =~ "не выбрано"

      # Положительный контроль: после выбора та же шапка называет уже сделанное.
      view |> element("#section-alignment-toggle") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      assert render(element(view, "#section-alignment-toggle")) =~ "Lawful Good"
    end

    # ⚠️ Задача 3.30 (решение Dan 15.08.2026): здесь стоял тест «проводка хука
    # прокрутки на месте» — хук `.FocusPending` подвозил экран к первой секции
    # с `data-pending="1"`. Хук снят («принудительный скролл в следующую
    # секцию не понравился»), и вместе с ним ушли `phx-hook` и `data-active`
    # с `#stage-body`. Проверять теперь нечего — но `data-pending` жив
    # и остался тем же вопросом, просто читает его лента секций.
    test "решение на секции по-прежнему помечено — теперь для ленты, а не для хука", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Хука больше нет ни на сцене, ни где-либо ещё в теле уровня.
      refute has_element?(view, "#stage-body[phx-hook]")
      refute has_element?(view, "#stage-body[data-active]")

      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#section-feats[data-pending='1']")
    end

    # ⚠️ Четыре «умные» формулы. Каждая отвечает на «висит ли здесь решение»
    # ровно тем же выражением, что и до 3.18, — и находки задач 1.6, 1.8 и
    # 3.10 обязаны остаться видимыми в том же виде.
    test "1.6/1.8: статы ждут решения и когда очков не осталось, но пол нарушен", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Билд по ссылке в обход воронки `put_build/2`: все 30 очков потрачены,
      # а кастерский пол CHA 11 не выкуплен. «Ждёт, если свободно > 0» здесь
      # соврало бы — ровно та ложная законность из §1.6/§1.8.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: [:sorcerer],
          base_abilities: %{str: 18, dex: 12, con: 16, int: 8, wis: 8, cha: 8}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-0") |> render_click()

      assert render(element(view, "#point-buy-budget b")) =~ "0"
      assert has_element?(view, "#section-point-buy[data-pending='1']")

      # Положительный контроль: тот же билд с выкупленным полом решения
      # больше не держит, хотя свободных очков так же нет.
      legal =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: [:sorcerer],
          base_abilities: %{str: 17, dex: 14, con: 14, int: 9, wis: 9, cha: 11}
        )

      {:ok, view2, _html} = live(conn, ~p"/?b=#{Encoding.encode(legal)}")
      view2 |> element("#level-0") |> render_click()

      assert render(element(view2, "#point-buy-budget b")) =~ "0"
      assert has_element?(view2, "#section-point-buy[data-pending='0']")
    end

    test "3.10: у волшебника НЕОБЯЗАТЕЛЬНЫЙ выбор школы всё равно висит решением", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      # `ClassChoices.complete?/3` для `required?: false` тривиально `true`
      # ещё до первого клика — если бы формула спрашивала его, экран не
      # подвёз бы игрока к выбору школы вовсе.
      assert has_element?(view, "#section-domains[data-pending='1']")

      view |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      assert has_element?(view, "#section-domains[data-pending='0']")
      assert has_element?(view, "#section-domains-body")
    end

    test "фиты и навыки: решение висит, пока слот пуст и пока очки не потрачены", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#section-feats[data-pending='1']")
      assert has_element?(view, "#section-skills[data-pending='1']")

      # ⚠️ Не Toughness: на Сиале Fighter выдаёт его на 1-м уровне даром, и в
      # списке доступных его нет вовсе (см. раздел «не предлагаем то, что и так
      # дадут»). И не Dodge: у свежего билда все статы на полу 8, а Dodge
      # требует DEX 13 — он лежит среди недоступных с причиной.
      view |> element("#feat-ok-alertness") |> render_click()
      view |> element("#level-1") |> render_click()

      # Fighter 1 даёт два слота (общий и бонусный), так что после одного
      # фита решение всё ещё висит — это и есть положительный контроль:
      # `data-pending` считает слоты, а не факт клика.
      assert has_element?(view, "#section-feats[data-pending='1']")
      assert has_element?(view, "#section-feats-body")
    end

    test "20-й уровень кастера: секция заклинаний держит решение из-за предупреждения", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: List.duplicate(:sorcerer, 25),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 14}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-25") |> render_click()

      # Стена 20-го уровня: новых заклинаний нет, но сказать об этом обязаны —
      # на этой ошибке теряют полбилда (CLAUDE.md §6).
      assert has_element?(view, "#spell-note")
      assert has_element?(view, "#section-spells[data-pending='1']")
    end
  end

  # Лента секций — замена двум снятым автодвижениям (задача 3.30, решение Dan
  # 15.08.2026). ⚠️ Липкость, прокрутку к якорю и горизонтальную ленту
  # `Phoenix.LiveViewTest` проверить не может: CSS он не применяет, JS не
  # выполняет. Здесь под тестом ровно то, что от него зависит, — состав
  # ленты, состояния и проводка; вид проверен глазами в headless Chrome
  # (360/390/430/768/1440, обе темы).
  describe "лента секций (задача 3.30)" do
    # 🔴 Сторож от расхождения: список секций живёт ДВАЖДЫ — условиями `:if`
    # в шаблоне и таблицей `nav_sections/1` в модуле. Копия, которую никто
    # не сверяет, разъезжается на первой же правке, а лента, ведущая к
    # несуществующей секции, — это ссылка в никуда.
    test "лента называет ровно те секции, что нарисованы", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert_nav_matches_sections(view)

      view |> element("#class-card-cleric") |> render_click()
      assert_nav_matches_sections(view)

      # Соркерер: добавляется секция заклинаний, которой нет у остальных.
      sorcerer =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: List.duplicate(:sorcerer, 4),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 14}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(sorcerer)}")
      assert_nav_matches_sections(view)

      # Уровень, кратный четырём: прибавка к характеристике, и ни расы,
      # ни мировоззрения, ни статов — они живут только на 1-м.
      view |> element("#level-4") |> render_click()
      assert_nav_matches_sections(view)
      assert has_element?(view, "#stage-nav-increase")
      refute has_element?(view, "#stage-nav-race")
    end

    # Задача 3.32 завела «пять янтарных секций на 1-м уровне», 3.68 добавила
    # к ним расу и мировоззрение цветом (без запрета), 3.69 переносит расу
    # и мировоззрение из `creation_hold?/2` в `holds_level?/2` — регрессия
    # на этот перенос: цвет пяти секций обязан остаться тем же самым, только
    # источник правила сменился.
    test "все пять секций 1-го уровня по-прежнему янтарные, пока не заполнены",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for key <- ~w(race alignment class point_buy) do
        assert has_element?(view, "#stage-nav-#{key}[data-state='hold']")
      end

      view |> element("#class-card-fighter") |> render_click()
      assert has_element?(view, "#stage-nav-feats[data-state='hold']")

      # Класс закрыт выбором, а раса/мировоззрение/поинт-бай — по-прежнему нет.
      assert has_element?(view, "#stage-nav-class[data-state='done']")

      for key <- ~w(race alignment point_buy) do
        assert has_element?(view, "#stage-nav-#{key}[data-state='hold']")
      end
    end

    # ⚠️ Задача 3.69 (ПЕРЕСМОТР 3.68, Dan 21.08.2026): раньше «класс взят»
    # уже открывало переход. Теперь причин недоступности до трёх, и каждая
    # называет ровно то, чего не хватает — тест проходит все три ступени,
    # а не только «было/стало».
    test "пункт ленты ведёт на якорь своей секции", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#stage-nav-race[href='#section-race']")
      assert has_element?(view, "#stage-nav-class[href='#section-class']")

      # Шаг вперёд заодно приводит экран к началу нового уровня — якорем,
      # а не хуком (см. разметку). Без класса шагать некуда, поэтому здесь
      # ссылки нет вовсе, а причина есть.
      # ⚠️ Задача 3.32: `#stage-nav-why` переименован в `#stage-nav-next-why` —
      # разметка кнопки стала общей на два места (лента и лестница), и id
      # внутренностей выводятся из id самой кнопки, иначе они совпали бы.
      refute has_element?(view, "#stage-nav-next[href]")
      assert has_element?(view, "#stage-nav-next-why", "сначала класс")

      # Раса и мировоззрение сами по себе класс не заменяют — причина
      # остаётся той же, пока класса нет вовсе (задача 3.69: `active > taken`
      # перебивает нехватку расы/мировоззрения, а не складывается с ней).
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      refute has_element?(view, "#stage-nav-next[href]")
      assert has_element?(view, "#stage-nav-next-why", "сначала класс")

      # Класс есть, а раса и мировоззрение — нет: теперь недостаёт именно их,
      # и кнопка называет ИХ, а не класс (проверено бы отдельным билдом ниже,
      # здесь — обратный порядок выбора, чтобы не плодить второй `live/2`).
      view |> element("#class-card-fighter") |> render_click()
      assert has_element?(view, "#stage-nav-next[href='#stage-head']")
      refute has_element?(view, "#stage-nav-next-why")
    end

    # 🔴 Задача 3.69: тот же сценарий, но раса и мировоззрение выбраны ПОСЛЕ
    # класса, а не до, — порядок выбора свободный (§3 CLAUDE.md, «класс
    # в игре выбирается до статов», про расу такого правила нет).
    test "переход недоступен, пока не выбраны и класс, и раса, и мировоззрение",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#class-card-fighter") |> render_click()
      refute has_element?(view, "#stage-nav-next[href]")
      assert has_element?(view, "#stage-nav-next-why", "сначала раса и мировоззрение")

      view |> element("#race-card-human") |> render_click()
      refute has_element?(view, "#stage-nav-next[href]")
      assert has_element?(view, "#stage-nav-next-why", "сначала мировоззрение")

      view |> element("#alignment-lawful_good") |> render_click()
      assert has_element?(view, "#stage-nav-next[href='#stage-head']")
      refute has_element?(view, "#stage-nav-next-why")
    end

    # Задача 3.32, п. 5 отзыва Dan: «тянуться туда каждый раз кажется
    # неудобным. Её бы переместить, может разместить рядом с лестницей?»
    # Копия шага вперёд живёт у лестницы; какая из двух видна — решает
    # медиа-запрос, а не разметка, поэтому в DOM они обе.
    test "шаг вперёд есть и у лестницы, и в ленте — одинаковый", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Без класса обе недоступны и обе называют причину.
      assert has_element?(view, "#spine-next[data-disabled='1']")
      assert has_element?(view, "#spine-next-why")

      # Задача 3.69: класса одного мало — нужны ещё раса и мировоззрение.
      view |> element("#class-card-fighter") |> render_click()
      assert has_element?(view, "#spine-next[data-disabled='1']")
      assert has_element?(view, "#spine-next-why", "сначала раса и мировоззрение")

      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      assert has_element?(view, "#spine-next[href='#stage-head']")
      refute has_element?(view, "#spine-next-why")

      # И она ведёт туда же: клик по копии у лестницы переводит уровень.
      view |> element("#spine-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")
    end

    # 🔴 Главная находка задачи: `data-pending="1"` склеивал «держит уровень»
    # и «можно доделать», и хук увозил экран к нерастраченным очкам навыков —
    # к тому, что игрок сознательно решил не тратить. В ленте это ДВА разных
    # состояния, и оба видны на одном экране одновременно.
    test "держит уровень и можно доделать — разные состояния", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#class-card-fighter") |> render_click()

      # Пустой слот фита держит.
      assert has_element?(view, "#stage-nav-feats[data-state='hold']")
      # Нерастраченные очки навыков — нет.
      assert has_element?(view, "#stage-nav-skills[data-state='todo']")
      # Сделанное — тише всех.
      assert has_element?(view, "#stage-nav-class[data-state='done']")

      # ⚠️ Обе секции помечены одним и тем же `data-pending="1"` — то есть
      # разница именно в ленте, а не в атрибуте, из которого она выведена.
      assert has_element?(view, "#section-feats[data-pending='1']")
      assert has_element?(view, "#section-skills[data-pending='1']")
    end

    # Задача 3.32, требование Dan 15.08.2026: «на этапе создания персонажа
    # "Характеристики" должны быть выделены обязательным цветом, в поинт-бае
    # должно остаться 0 очков, после этого они считаются заполненными».
    #
    # ⚠️ Здесь эта же секция раньше проверялась как `todo` — вместе с навыками,
    # под общим доводом «нерастраченные очки уровень не держат». Довод не
    # отменён: `level_settled?/3` не тронут, и это проверяется следующим
    # тестом. Изменился только голос ленты на СОЗДАНИИ персонажа.
    test "на уровне 1 характеристики горят обязательным цветом, пока есть что тратить",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#class-card-fighter") |> render_click()
      assert has_element?(view, "#stage-nav-point_buy[data-state='hold']")

      # «Заполнено» — это ровно `свободно == 0`, никакой новой формулы:
      # шесть характеристик по 13 стоят ровно 30 очков бюджета.
      spent =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 13, dex: 13, con: 13, int: 13, wis: 13, cha: 13}
        )

      {:ok, spent_view, _html} = live(conn, ~p"/?b=#{Encoding.encode(spent)}")

      # ⚠️ Билд из ссылки открывается на СЛЕДУЮЩЕМ уровне, а секция статов
      # живёт только на первом — без этого клика проверять было бы нечего.
      spent_view |> element("#level-1") |> render_click()
      assert has_element?(spent_view, "#stage-nav-point_buy[data-state='done']")
    end

    # 🔴 Обратная сторона того же требования: цвет — сигнал игроку, а не новое
    # игровое правило. Нераспределённые очки левелап НЕ держат, и уйти вперёд
    # с ними можно (в игре так и есть), поэтому кнопка перехода про них молчит.
    test "но уровень нераспределённые очки не держат", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса и мировоззрение держат переход, поинт-бай — нет.
      # Оба нужны здесь, чтобы дойти до собственно проверяемого правила.
      # ⚠️ Дварф, а не человек: у человека есть СВОЙ дополнительный слот
      # фита 1-го уровня (`extra_feats`, «фит расы»), и он остался бы
      # незаполненным — а тест как раз про «слоты полны, ничего не держит».
      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#feat-ok-alertness") |> render_click()
      view |> element("#feat-ok-blind_fight") |> render_click()

      # Очки поинт-бая не тронуты — и лента про них всё ещё горит…
      assert has_element?(view, "#stage-nav-point_buy[data-state='hold']")

      # …а уровень при этом закрыт: кнопка перехода без янтаря, и шаг проходит.
      refute has_element?(view, "#stage-nav-next[data-hold='1']")
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")
    end
  end

  # Задача 3.69 (Dan 21.08.2026, ПЕРЕСМОТР 3.68): «кнопку перевода на
  # 2 уровень я бы все-таки блокировал, пока раса и мировоззрение не
  # выбраны, так будет логичнее». `level_ceiling/2` — ОДИН потолок на
  # кнопку (проверено выше, describe "лента секций") И на клик по
  # лестнице (здесь) — два органа управления одного действия обязаны
  # соглашаться (CLAUDE.md §8, форма бага 1.2).
  #
  # Таблица случаев — прямо из постановки задачи:
  #
  #   | билд                          | taken | потолок | смысл           |
  #   |-------------------------------|-------|---------|-----------------|
  #   | пусто                         | 0     | 1       | сидим на созд.  |
  #   | класс взят, расы нет          | 1     | 1       | на 2-й не пускает |
  #   | раса и мировоззрение есть     | 1     | 2       | пускает         |
  #   | старый билд без расы, 5 ур.   | 5     | 5       | листать можно, добавить — нет |
  describe "потолок лестницы без расы и мировоззрения (задача 3.69)" do
    test "пустой билд — потолок 1, клик по 2-му уровню не двигает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#stage-title", "Уровень 1")
      view |> element("#level-2") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 1")
    end

    test "класс взят, расы нет — потолок 1, на 2-й не пускает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-2") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 1")
    end

    test "раса и мировоззрение есть — потолок 2, пускает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#class-card-fighter") |> render_click()
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()

      view |> element("#level-2") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")
    end

    # 🔴 Регрессия, ради которой сформулирована таблица выше: ссылка старше
    # правила «раса обязательна» (или билд, собранный в обход веб-слоя)
    # обязана листаться как прежде — блокируется только ДОБАВЛЕНИЕ нового
    # уровня, а не просмотр уже взятых. Билд, выдёргивающий такую ссылку
    # на 1-й уровень, был бы регрессией хуже того бага, который эта задача
    # чинит.
    test "старый билд без расы: пять уровней листаются, шестой не добавляется", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:fighter, 5))
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Ссылка открывается на последнем ВЗЯТОМ уровне — потолок без расы
      # равен `taken`, а не `taken + 1`.
      assert has_element?(view, "#stage-title", "Уровень 5")

      # Листать уже взятое можно вплоть до самого низа.
      view |> element("#level-1") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 1")

      view |> element("#level-3") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 3")

      view |> element("#level-5") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 5")

      # А новый, 6-й — нет, и кнопка называет ровно то, чего не хватает.
      view |> element("#level-6") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 5")
      refute has_element?(view, "#stage-nav-next[href]")
      assert has_element?(view, "#stage-nav-next-why", "сначала раса и мировоззрение")

      # Стоит назвать оба (с 1-го уровня, где живёт этот выбор) — потолок
      # отпускает сам, без переоткрытия ссылки.
      view |> element("#level-1") |> render_click()
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()

      view |> element("#level-6") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 6")
    end

    # 🔴 Тот же потолок, но через ВТОРОЙ вход — адрес `?l=` (задача 3.61),
    # а не клик по лестнице. `load_code/3` обязан звать ту же самую
    # `level_ceiling/2`, а не второй, переписанный вручную вариант формулы
    # (форма бага 1.2, CLAUDE.md §8) — иначе открытая по прямой ссылке `?l=`
    # позиция и позиция после клика могли бы разойтись.
    test "старый билд без расы: ?l= листает взятое, но не запрашиваемое сверх потолка",
         %{conn: conn, ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:fighter, 5))
      code = Encoding.encode(build)

      {:ok, mid, _html} = live(conn, ~p"/?b=#{code}&l=3")
      assert has_element?(mid, "#stage-title", "Уровень 3")

      # `l=6` просит уровень за потолком (5, не 6, — расы нет) и зажимается
      # до последнего взятого, а не до `taken + 1`, как было бы с расой.
      {:ok, over, _html} = live(conn, ~p"/?b=#{code}&l=6")
      assert has_element?(over, "#stage-title", "Уровень 5")
    end
  end

  # `has_element?/2` возвращает булево, поэтому сверка идёт сравнением
  # ответов, а не разбором сырого HTML (AGENTS.md).
  defp assert_nav_matches_sections(view) do
    for {key, id} <- [
          {"race", "section-race"},
          {"alignment", "section-alignment"},
          {"class", "section-class"},
          {"point_buy", "section-point-buy"},
          {"domains", "section-domains"},
          {"increase", "section-increase"},
          {"feats", "section-feats"},
          {"spells", "section-spells"},
          {"skills", "section-skills"}
        ] do
      assert has_element?(view, "##{id}") == has_element?(view, "#stage-nav-#{key}"),
             "секция ##{id} и пункт ленты #stage-nav-#{key} разошлись: " <>
               "секция #{has_element?(view, "##{id}")}, пункт #{has_element?(view, "#stage-nav-#{key}")}"
    end
  end

  # Задача 3.8 (04.08.2026, Dan: «тут на скрине много лишнего текста»). Три
  # рода текста, три разных судьбы (CLAUDE.md §6): объяснение НАШИХ решений —
  # убрать совсем; дубль того, что уже написано на карточке, — убрать;
  # признание в непосчитанном — не удалить, а переселить туда, где оно
  # действительно видно.
  describe "вычистить пояснительный текст (задача 3.8)" do
    test "секция расы не объясняет свои же решения и не пересказывает то, что и так на карточках",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      race_section = render(element(view, "#section-race"))
      refute race_section =~ "механическое имя движка подписью"
      refute race_section =~ "Дан подтвердил"
      refute race_section =~ "Осторожно с коллизией"

      # Положительный контроль: то же самое видно без единого слова прозы —
      # `ru`/`en` стоят прямо на карточке, в месте выбора.
      card = render(element(view, "#race-card-dwarf"))
      assert card =~ "Гном"
      assert card =~ "Dwarf"
    end

    test "секция класса не объясняет, почему недоступное показано, а не спрятано", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()

      class_section = render(element(view, "#section-class"))
      refute class_section =~ "часть обучения правилам"
      refute class_section =~ "не спрятаны"

      # Положительный контроль: причина всё равно на месте — на самой
      # запертой карточке, глифом замка и текстом рядом.
      assert render(element(view, "#class-lock-arcane_archer")) =~ "🔒"
    end

    test "секция фитов не объясняет прозой то, что каждая недоступная строка и так печатает",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      view |> element("#level-1") |> render_click()

      feats_section = render(element(view, "#section-feats"))
      refute feats_section =~ "а не спрятаны"

      # Положительный контроль: причина печатается у каждой недоступной
      # строки (`entry.reason_texts`), а не только заявлена прозой сверху.
      assert has_element?(view, "#feats-blocked .feat-why")
    end

    # ⚠️ Задача 3.17: было «нулевой уровень описан одной фразой» — теперь это
    # ПРЕФИКС уровня 1 (`stage_sub/3`), а не отдельная фраза отдельного
    # экрана. Проверяемое поведение не изменилось ни на бит (фраза всё ещё
    # видна одной строкой без клика), меняется только то, что она называет.
    test "первый уровень называет расу, мировоззрение и статы, без пояснения «влияет на каждый уровень ниже»",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      sub = render(element(view, "#stage-sub"))
      assert sub =~ "Раса"
      assert sub =~ "мировоззрение"
      assert sub =~ "стартовые характеристики"
      refute sub =~ "влияет на каждый уровень"
    end

    # ⚠️ Про то, что оба переселённых гэпа (расовые/оружейные бонусы, кап
    # +12) доехали до панели итогов и видны БЕЗ единого клика — отдельного
    # теста тут нет специально: describe «характеристики переехали в панель
    # итогов (задача 3.2)» → «заметка не поминает Great strength…» уже
    # проверяет ровно это, тем же вызовом `live(conn, ~p"/")` без клика.
    # Второй тест на тот же факт добавил бы строк, не добавив покрытия.
  end

  # Правило измерено в игре (Dan, тестовый сервер, 03.08.2026): ключевая
  # характеристика заклинателя не опускается ниже 11 ИТОГОВЫХ, и минимум
  # выкупается принудительно. Здесь проверяется не арифметика (она в
  # `point_buy_test.exs`), а то, что игрок видит, куда делись очки.
  describe "минимум ключевой характеристики кастера" do
    # ⚠️ Пока класс первого уровня не выбран, доступный бюджет НЕИЗВЕСТЕН:
    # 30, 27 или 25 решают раса и класс вместе. Напечатать 30 молча — ложь
    # по умолчанию, поэтому строка стоит на экране с самого начала.
    test "до выбора класса бюджет назван неокончательным", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert render(element(view, "#point-buy-floor")) =~ "не окончательный"
    end

    test "кастер на первом уровне выкупает минимум и говорит, куда ушли очки", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-half_orc") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-sorcerer") |> render_click()
      view |> element("#level-0") |> render_click()

      # Раса даёт −2, поэтому покупается 13, а в степпере (задача 3.156, как
      # в игре) стоит итог — те самые 11.
      assert render(element(view, "#point-buy-cha .val")) =~ "11"
      assert render(element(view, "#point-buy-budget b")) =~ "25"

      note = render(element(view, "#point-buy-floor"))
      assert note =~ "Sorcerer"
      assert note =~ "CHA"
      assert note =~ "25"

      # Отобрать выкупленное нельзя — это вторая половина правила.
      assert has_element?(view, "#point-buy-cha-down[disabled]")
    end

    test "человек-кастер: минимум 11, свободных 27", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      view |> element("#level-0") |> render_click()

      assert render(element(view, "#point-buy-wis .val")) =~ "11"
      assert render(element(view, "#point-buy-budget b")) =~ "27"
    end

    # Положительный контроль: у не-кастера не выкупается ничего, и строки
    # с объяснением нет вовсе — иначе тест «минимум работает» зеленел бы
    # и у реализации, которая подняла пол всем классам разом.
    test "воин: характеристика опускается до 8, бюджет остаётся 30", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-0") |> render_click()

      assert render(element(view, "#point-buy-wis .val")) =~ "8"
      assert render(element(view, "#point-buy-budget b")) =~ "30"
      assert has_element?(view, "#point-buy-wis-down[disabled]")
      refute has_element?(view, "#point-buy-floor")
    end

    # ⚠️ Задача 3.17 переписала исход этого теста, а не только навигацию.
    # Раньше здесь стояло «класс выбирается ДО статов, а у нас после» — это
    # было верно ДО слияния нулевого и первого уровней и перестало быть
    # верным вместе с ним (оба теперь на одном экране, порядок свободный).
    # Билд по ссылке всё ещё может прийти с нелегальной покупкой (источник —
    # чужие руки, не наш поинт-бай), и первая правка всё ещё проводит его
    # через воронку `put_build/2` — но с решением 3 задачи 3.17 воронка НЕ
    # уводит бюджет в минус, а сбрасывает распределение целиком, если
    # принудительная покупка не помещается в свободные очки. Старый исход
    # («минус в бюджете») зафиксирован в комментарии как то, чем это БЫЛО, —
    # HANDOFF.md: неверная справка дороже отсутствующей, поэтому переписан,
    # а не удалён молча.
    test "билд из ссылки не переписывается, но первая правка сбрасывает нелегальную покупку",
         %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: [:sorcerer],
          base_abilities: %{str: 18, dex: 12, con: 16, int: 8, wis: 8, cha: 8}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-0") |> render_click()

      # Чужой билд открывается ровно таким, каким его прислали (решение 1.7),
      # — но строка уже говорит, что минимум 11, а кнопка «−» у CHA
      # заблокирована.
      assert render(element(view, "#point-buy-cha .val")) =~ "8"
      assert has_element?(view, "#point-buy-cha-down[disabled]")
      assert render(element(view, "#point-buy-floor")) =~ "11"
      refute has_element?(view, "#point-buy-reset")

      # Первая же правка проводит билд через воронку `put_build/2`. CHA 11
      # стоит 3 очка, а свободных — 0 (все 30 уже потрачены на STR/DEX/CON):
      # принудительная покупка не помещается, значит распределение сбрасывается
      # к табличному полу целиком, а не уходит в минус (AGENT_QUEUE §3.17,
      # решение 3).
      view |> element("#alignment-lawful_good") |> render_click()

      assert render(element(view, "#point-buy-str .val")) =~ "8"
      assert render(element(view, "#point-buy-cha .val")) =~ "11"
      assert render(element(view, "#point-buy-budget b")) =~ "27"
      refute has_element?(view, "#point-buy-budget[data-over='1']")

      # Сброс сказан словами и подсвечен по строкам — не флешем, который
      # погас бы на следующем же клике.
      assert has_element?(view, "#point-buy-reset")
      assert render(element(view, "#point-buy-reset")) =~ "STR"
      assert has_element?(view, "#point-buy-str[data-reset='1']")
      refute has_element?(view, "#point-buy-int[data-reset='1']")
    end

    # Положительный контроль ко всему разделу выше: сброс срабатывает именно
    # от НЕХВАТКИ очков, а не от самого факта смены класса. Тот же переезд
    # пола (соркерер → клирик), но со свободными очками с запасом — обычный
    # верхний прогон `enforce_floor/2`, без единого сброшенного значения.
    test "кастер → кастер с запасом очков переезжает пол без сброса", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()
      view |> element("#class-card-sorcerer") |> render_click()

      assert render(element(view, "#point-buy-cha .val")) =~ "11"
      refute has_element?(view, "#point-buy-reset")

      # ⚠️ Задача 3.18: клика по `#section-class-toggle` здесь больше нет —
      # секция класса не сворачивается сама, карточки на месте.
      view |> element("#class-card-cleric") |> render_click()

      assert render(element(view, "#point-buy-wis .val")) =~ "11"

      # Купленная CHA — не наша, чтобы забирать (решение 3): осталась на 11.
      assert render(element(view, "#point-buy-cha .val")) =~ "11"
      refute has_element?(view, "#point-buy-reset")
      refute has_element?(view, "#point-buy-str[data-reset='1']")
    end

    # Обратный пример Dan: воин с WIS 8, взявший клирика ВТОРЫМ уровнем, класс
    # получает и минимума не держит. Кастовать он всё равно не будет — это уже
    # `casts_spell_level`, и его мы здесь не трогаем.
    test "клирик вторым уровнем ничего не выкупает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-2") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      view |> element("#level-0") |> render_click()

      assert render(element(view, "#point-buy-wis .val")) =~ "8"
      assert render(element(view, "#point-buy-budget b")) =~ "30"
      refute has_element?(view, "#point-buy-floor")
    end
  end

  describe "choosing a class" do
    test "taking a level updates the split and the totals", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      assert has_element?(view, "#class-card-fighter")

      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#split-fighter")
      assert render(element(view, "#character-level")) =~ "1"
      assert render(element(view, "#level-1")) =~ "Fighter"
    end

    test "a locked class is shown with its reason rather than hidden", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()

      # Prestige classes cannot be taken at level 1; the card stays on screen.
      assert has_element?(view, "#class-card-dwarven_defender")
      assert has_element?(view, "#class-card-dwarven_defender[disabled]")
      assert has_element?(view, "#class-lock-dwarven_defender")
    end

    test "the class limit is reported in Russian once four classes are used", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса и мировоззрение — один раз, до цикла, иначе
      # потолок лестницы не пустит дальше уровня 1 вовсе.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()

      # Выбор класса больше не перебрасывает на следующий уровень сам: уровень
      # держат незакрытые решения (фиты, прибавка к стату). Поэтому уровни
      # здесь переключаются явно.
      for {class, level} <- Enum.with_index(~w(fighter cleric rogue sorcerer), 1) do
        view |> element("#level-#{level}") |> render_click()
        view |> element("#class-card-#{class}") |> render_click()
      end

      # A fifth distinct class is now refused by the core, and we word the refusal.
      view |> element("#level-5") |> render_click()
      assert render(element(view, "#class-lock-wizard")) =~ "лимит"
    end

    # Лимит классов — свойство ГОТОВОГО билда, а не уровней до текущего. Правя
    # середину собранного билда, легко не заметить, что четыре класса уже
    # заняты: уровни после правимого тоже считаются (`LevelUp` получает `at:`).
    test "лимит классов считается по всему билду, а не по уровням до текущего", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels:
            List.duplicate(:fighter, 10) ++
              List.duplicate(:cleric, 10) ++
              List.duplicate(:rogue, 10) ++ List.duplicate(:sorcerer, 11)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Пятый уровень — Fighter, и до него использован ровно один класс.
      view |> element("#level-5") |> render_click()

      assert render(element(view, "#class-lock-wizard")) =~ "лимит"

      # А класс, уже присутствующий в билде, никуда не делся.
      refute has_element?(view, "#class-lock-rogue")
    end

    test "dropping the last level shortens the build", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      assert render(element(view, "#character-level")) =~ "1"

      view |> element("#drop-level") |> render_click()
      assert render(element(view, "#character-level")) =~ "0"
    end
  end

  # ⚠️ Строка-переход «Часть классов недоступна без мировоззрения» + кнопка
  # убраны по решению Dan 05.08.2026. Замок и его причина остаются — они
  # и учат правилу (CLAUDE.md §6), а отдельная строка над сеткой повторяла
  # то, что каждая запертая карточка уже говорит про себя сама.
  describe "замок класса без мировоззрения (задача 3.17)" do
    test "класс с ограничением заперт и причина названа", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Monk — Lawful, и мировоззрение ещё не выбрано.
      assert has_element?(view, "#class-card-monk[disabled]")
      assert render(element(view, "#class-lock-monk")) =~ "Lawful"
    end

    test "выбор подходящего мировоззрения снимает замок с конкретного класса", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#class-lock-monk")

      view |> element("#alignment-lawful_good") |> render_click()

      refute has_element?(view, "#class-lock-monk")
      refute has_element?(view, "#class-card-monk[disabled]")
    end
  end

  describe "feats" do
    # ⚠️ STR 13 здесь не украшение: с тех пор как список спрашивает ядро про
    # требования, `Power attack` (нужна СИЛА 13) при СИЛЕ 10 лежит в недоступных.
    # Раньше тесты этого не замечали, потому что требования не проверялись вовсе,
    # и «доступен» значило «не отфильтрован». Персонаж, который берёт Power
    # attack, обязан ему соответствовать — это и есть предмет проверки.
    setup %{conn: conn} do
      ruleset = Data.ruleset!(Data.default_version())

      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "level one grants a general slot and a Fighter bonus slot", %{view: view} do
      assert has_element?(view, "#slot-chip-general")
      assert has_element?(view, "#slot-chip-class_bonus-fighter")
    end

    # Iron will, not Toughness: Siala hands Toughness to a Fighter on his first
    # level, so it is no longer offered there at all (see the block below).
    test "picking a feat fills a slot and clearing it empties the slot again", %{view: view} do
      view |> element("#feat-ok-iron_will") |> render_click()

      assert has_element?(view, "#slot-chip-general[data-filled='1']")
      assert render(element(view, "#slot-chip-general")) =~ "Iron will"

      view |> element("#slot-clear-general") |> render_click()
      refute has_element?(view, "#slot-chip-general[data-filled='1']")
    end

    test "the narrowest slot is spent first: a Fighter bonus before the general one", %{
      view: view
    } do
      # Power attack is on Fighter's bonus list, so the bonus slot pays for it
      # and the general slot stays free (CLAUDE.md §6).
      view |> element("#feat-ok-power_attack") |> render_click()

      assert has_element?(view, "#slot-chip-class_bonus-fighter[data-filled='1']")
      refute has_element?(view, "#slot-chip-general[data-filled='1']")
    end

    test "fuzzy search finds Power attack by pwatk", %{view: view} do
      view
      |> form("#feat-search-form", %{"q" => "pwatk"})
      |> render_change()

      assert has_element?(view, "#feat-ok-power_attack")
      refute has_element?(view, "#feat-ok-toughness")
    end

    test "unavailable feats are listed with a reason instead of hidden", %{view: view} do
      view
      |> form("#feat-search-form", %{"q" => "epic toughness"})
      |> render_change()

      assert has_element?(view, "#feat-no-epic_toughness")
      assert render(element(view, "#feat-no-epic_toughness")) =~ "эпический"
    end

    test "a slot chip filters the list to what that slot accepts", %{view: view} do
      view |> element("#slot-filter-class_bonus-fighter") |> render_click()

      assert has_element?(view, "#slot-filter-hint")
      # Toughness is not on anybody's bonus list, so the Fighter slot refuses it.
      refute has_element?(view, "#feat-ok-toughness")
    end

    # AGENT_QUEUE.md 3.50, part B: both sides of the fallback, both lists.
    # `weapon_focus` and `epic_skill_focus` are two of the 23 feats with no
    # Fandom art at all (one page per whole tiered family) — not a data gap.
    test "an icon-bearing feat shows its art, the other shows only the glyph", %{view: view} do
      assert has_element?(view, "#feat-ok-iron_will .game-icon img")
      refute has_element?(view, "#feat-ok-iron_will .game-icon i")

      refute has_element?(view, "#feat-ok-weapon_focus .game-icon img")
      assert has_element?(view, "#feat-ok-weapon_focus .game-icon i")
    end

    test "the fallback glyph shows on the blocked list too, same as before this task", %{
      view: view
    } do
      view
      |> form("#feat-search-form", %{"q" => "epic skill focus"})
      |> render_change()

      assert has_element?(view, "#feat-no-epic_skill_focus")
      refute has_element?(view, "#feat-no-epic_skill_focus .game-icon img")
      assert has_element?(view, "#feat-no-epic_skill_focus .game-icon i")
    end
  end

  # Task 3.87 (Dan 24.08.2026) — a hover/click/tap trigger beside a feat's
  # name that opens onto its Fandom "Specifics" prose, marked when the shard
  # rewrote the feat. `Phoenix.LiveViewTest` never runs JS (AGENTS.md), so
  # these tests only reach what the server renders — the trigger `<span>`
  # and its `data-*` payload — never the JS-built floating panel itself
  # (`BuilderComponents.feat_info/1`'s `.FeatInfo` hook); that half is
  # checked live in a real browser, not here.
  describe "«что делает фит» — попап/шторка (задача 3.87)" do
    setup %{conn: conn} do
      ruleset = Data.ruleset!(Data.default_version())

      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    # ⚠️ `info-` LEADS the id (`info-feat-ok-…`), not trails it
    # (`feat-ok-…-info`): a regression test elsewhere in this file
    # («холодный старт по ссылке не смешивает потоки фитов», задача 3.66)
    # matches every element whose id *starts with* `feat-ok-`/`feat-no-` and
    # compares that set against the picker's own truth — a trailing suffix
    # collided with that prefix and inflated the set. Found by that test,
    # not designed around it up front.
    test "an available feat's row carries an info trigger with its description", %{view: view} do
      assert has_element?(view, "#info-feat-ok-iron_will")

      html = render(element(view, "#info-feat-ok-iron_will"))
      assert html =~ "will saving throws"
      refute html =~ "[["
      assert html =~ "aria-label=\"Что делает Iron will\""
    end

    test "a blocked feat's row carries the trigger too — the row being disabled must not silence it",
         %{view: view} do
      view |> form("#feat-search-form", %{"q" => "epic toughness"}) |> render_change()

      assert has_element?(view, "#info-feat-no-epic_toughness")
    end

    test "a feat the shard rewrote is marked, with the shard's own quote", %{view: view} do
      view |> form("#feat-search-form", %{"q" => "evasion"}) |> render_change()

      trigger = element(view, "#info-feat-no-evasion")
      assert has_element?(view, "#info-feat-no-evasion")

      html = render(trigger)
      assert html =~ "data-feat-changed=\"true\""
      assert html =~ "Quillfire"
      refute html =~ "[["
    end

    test "a feat the shard rewrote administratively is still marked, with no quote to show", %{
      view: view
    } do
      trigger = element(view, "#info-feat-no-toughness")
      assert has_element?(view, "#info-feat-no-toughness")

      html = render(trigger)
      assert html =~ "data-feat-changed=\"true\""
      assert html =~ ~s(data-feat-notes="[]")
    end

    test "an unchanged feat carries no shard marking at all", %{view: view} do
      html = render(element(view, "#info-feat-ok-iron_will"))
      assert html =~ "data-feat-changed=\"false\""
    end

    # `Riding Sprint` — one of the eleven shard-only feats (CLAUDE.md §3):
    # no Fandom page, no English "Specifics" prose, and Dan asked (task 3.87)
    # for it to stay empty rather than translated from the shard's Russian
    # prose. The row still renders — it is a real, searchable feat — it
    # simply offers no trigger to open onto nothing.
    test "a Siala-only feat's row offers no info trigger at all", %{view: view} do
      view |> form("#feat-search-form", %{"q" => "riding sprint"}) |> render_change()

      assert has_element?(view, "#feat-no-riding_sprint") or
               has_element?(view, "#feat-ok-riding_sprint")

      refute has_element?(view, "#info-feat-no-riding_sprint")
      refute has_element?(view, "#info-feat-ok-riding_sprint")
    end
  end

  # AGENT_QUEUE.md 3.54: the icon REPLACES the slot-kind glyph on a filled
  # chip, same component `#feats-available`/`#feats-blocked` already use
  # (3.50) — not a second copy next to it, because the kind is already spelled
  # out in `.slot-label` right beside it. `favored_enemy` and `weapon_focus`
  # are both taken *with a choice* here on purpose (`{feat_id, choice}`,
  # `Rules.Build.feat_pick/0`): the icon is looked up by `feat_id`, and a pick
  # stored as a pair is exactly the shape that would break a lookup written
  # against a bare atom.
  describe "иконка в чипе слота — задача 3.54" do
    setup %{conn: conn} do
      ruleset = Data.ruleset!(Data.default_version())

      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: [:fighter],
          feats: %{
            1 => %{
              :general => {:favored_enemy, :goblinoid},
              {:class_bonus, :fighter} => {:weapon_focus, :longsword}
            }
          }
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "a filled slot whose feat carries art shows it, choice pair and all", %{view: view} do
      assert has_element?(view, "#slot-chip-general[data-filled='1'] .game-icon img")
      refute has_element?(view, "#slot-chip-general .game-icon i")
    end

    test "a filled slot whose feat carries no art falls back to the slot's own glyph", %{
      view: view
    } do
      # `weapon_focus` is one of the 23 icon-less feats (3.50) — the fallback
      # here is `slot.glyph` (kind of SLOT, "⚔︎" for a class bonus), not the
      # feat's own general/epic marker the way the feat list falls back.
      refute has_element?(view, "#slot-chip-class_bonus-fighter .game-icon img")
      assert has_element?(view, "#slot-chip-class_bonus-fighter .game-icon i")
    end

    test "an unfilled slot keeps showing its glyph, same as before this task", %{view: view} do
      refute has_element?(view, "#slot-chip-racial[data-filled='1']")
      refute has_element?(view, "#slot-chip-racial .game-icon img")
      assert has_element?(view, "#slot-chip-racial .game-icon i")
    end
  end

  # 🔴 Ranger class level 35 grants **two** bonus feats («at levels 23, 25, 26,
  # 29, 30, 32, 35(two bonus feats), 38, and 40» — `fandom:Ranger`), and until
  # 14.08.2026 the builder showed one chip and the player lost a whole feat.
  # The DOM is where the fix has to be visible: two chips with two ids, each
  # holding its own pick.
  describe "уровень, выдающий два бонусных слота (рейнджер 35)" do
    setup %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:ranger, 41),
          base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-35") |> render_click()
      %{view: view}
    end

    test "чипов два, а не один", %{view: view} do
      assert has_element?(view, "#slot-chip-class_bonus-ranger")
      assert has_element?(view, "#slot-chip-class_bonus-ranger-2")
    end

    test "первый занятый чип не мешает второму принять свой фит", %{view: view} do
      view |> element("#feat-ok-epic_prowess") |> render_click()

      assert has_element?(view, "#slot-chip-class_bonus-ranger[data-filled='1']")
      refute has_element?(view, "#slot-chip-class_bonus-ranger-2[data-filled='1']")

      view |> element("#feat-ok-epic_toughness") |> render_click()

      assert has_element?(view, "#slot-chip-class_bonus-ranger-2[data-filled='1']")
      assert render(element(view, "#slot-chip-class_bonus-ranger")) =~ "Epic prowess"
      assert render(element(view, "#slot-chip-class_bonus-ranger-2")) =~ "Epic toughness"
    end

    # Очистка адресуется тем же ключом слота, что и выбор: спутай их — и кнопка
    # «убрать» у второго чипа стирала бы пик первого.
    test "очистка второго слота не трогает первый", %{view: view} do
      view |> element("#feat-ok-epic_prowess") |> render_click()
      view |> element("#feat-ok-epic_toughness") |> render_click()

      view |> element("#slot-clear-class_bonus-ranger-2") |> render_click()

      assert has_element?(view, "#slot-chip-class_bonus-ranger[data-filled='1']")
      refute has_element?(view, "#slot-chip-class_bonus-ranger-2[data-filled='1']")
    end

    # Положительный контроль на соседний уровень: на 38-м слот один, то есть
    # «два» выше — свойство 35-го, а не всякого эпического уровня рейнджера.
    test "на 38-м классовом уровне чип по-прежнему один", %{view: view} do
      view |> element("#level-38") |> render_click()

      assert has_element?(view, "#slot-chip-class_bonus-ranger")
      refute has_element?(view, "#slot-chip-class_bonus-ranger-2")
    end
  end

  describe "skills" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "a rank is bought through the add list and then the stepper", %{view: view} do
      view |> element("#skill-add-toggle") |> render_click()
      view |> element("#skill-chip-discipline") |> render_click()

      assert has_element?(view, "#skill-row-discipline")
      assert render(element(view, "#skill-total-discipline")) =~ "1"

      view |> element("#skill-plus-discipline") |> render_click()
      assert render(element(view, "#skill-total-discipline")) =~ "2"

      view |> element("#skill-minus-discipline") |> render_click()
      assert render(element(view, "#skill-total-discipline")) =~ "1"
    end

    test "«макс» spends the rest of the budget in one click", %{view: view} do
      view |> element("#skill-add-toggle") |> render_click()
      view |> element("#skill-chip-discipline") |> render_click()

      assert render(element(view, "#skill-budget-free")) =~ "3"

      view |> element("#skill-max-discipline") |> render_click()

      # Тратить больше нечего — сводка шапки называет купленное (CLAUDE.md §6).
      # ⚠️ Задача 3.18: раньше здесь стоял `refute has_element?(view,
      # "#skill-budget-free")` — секция схлопывалась сама, и бюджет исчезал из
      # DOM вместе с телом. Теперь она открыта, поэтому проверяется само
      # утверждение («не осталось ни очка»), а не побочный эффект схлопывания.
      assert render(element(view, "#section-skills-toggle")) =~ "Discipline +4"
      assert render(element(view, "#skill-budget-free")) =~ "0"
      assert has_element?(view, "#section-skills[data-pending='0']")
    end

    test "the ladder marks a cross-class rank as twice the price", %{view: view} do
      view |> element("#skill-add-toggle") |> render_click()
      # Tumble is not a Fighter class skill, so it costs two points a rank.
      view |> element("#skill-chip-tumble") |> render_click()

      assert has_element?(view, "#level-1 [data-cross='1']")
    end
  end

  # ⚠️ source: Дан, наблюдение в игре 03.08.2026 (`source: user`) — «Sorcerer
  # 1–39, 40-м уровнем Fighter, 35 рангов Spellcraft: в игре на уровне воина
  # поднять его нельзя». Конструктор давал докачать до 43.
  describe "потолок рангов принадлежит уровню, а не билду" do
    setup %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(sorcerer_then_fighter(ruleset))}")
      %{view: view}
    end

    test "на уровне воина степпер упирается И называет причину", %{view: view} do
      view |> element("#level-40") |> render_click()

      assert has_element?(view, "#skill-plus-spellcraft[disabled]")
      assert has_element?(view, "#skill-max-spellcraft[disabled]")

      # ⚠️ Молча погашенная кнопка читается как поломка (CLAUDE.md §6).
      why = render(element(view, "#skill-why-spellcraft"))
      assert why =~ "потолок 21"
      assert why =~ "Fighter"
      assert why =~ "купленное остаётся"

      # …и купленные ранги на месте, а не отобраны.
      assert render(element(view, "#skill-total-spellcraft")) =~ "35"
    end

    # ⚠️ Кнопка гасится только разметкой, а событие может прийти и мимо неё
    # (LiveViewTest тем более не применяет CSS и не смотрит на `disabled`
    # при вызове по имени события). Отказывать обязан сервер.
    test "событие в обход погашенной кнопки ранга не добавляет", %{view: view} do
      view |> element("#level-40") |> render_click()
      before = render(element(view, "#skill-total-spellcraft"))

      render_click(view, "skill_rank", %{"skill" => "spellcraft", "delta" => "1"})
      render_click(view, "skill_max", %{"skill" => "spellcraft"})

      assert render(element(view, "#skill-total-spellcraft")) == before
    end

    # ⚠️ Чип «+ добавить навык» — второй вход в ту же покупку, и он умел
    # проваливаться молча: клик по эксклюзивному навыку на уровне, чей класс его
    # не даёт, просто ничего не делал. Fighter не качает Use Magic Device.
    test "закрытый чип погашен, а не молча мёртв", %{view: view} do
      view |> element("#level-40") |> render_click()
      view |> element("#skill-add-toggle") |> render_click()

      assert has_element?(view, "#skill-chip-use_magic_device[disabled]")
      assert render(element(view, "#skill-chip-use_magic_device")) =~ "не качает вовсе"

      # Положительный контроль: обычный кросс-классовый навык на том же уровне
      # берётся, и цена у него настоящая.
      refute has_element?(view, "#skill-chip-tumble[disabled]")
      assert render(element(view, "#skill-chip-tumble")) =~ "Кросс-классовый"
    end

    # ⚠️ Положительный контроль к обоим тестам выше: на 39-м, где класс уровня
    # соркерер, тот же навык на той же машинерии поднимается. Без него «нельзя»
    # зеленело бы и при полностью сломанной покупке рангов.
    test "на уровне соркерера тот же навык поднимается и причины нет", %{view: view} do
      view |> element("#level-39") |> render_click()

      assert has_element?(view, "#skill-plus-spellcraft")
      refute has_element?(view, "#skill-plus-spellcraft[disabled]")
      refute has_element?(view, "#skill-why-spellcraft")

      view |> element("#skill-plus-spellcraft") |> render_click()

      assert render(element(view, "#skill-total-spellcraft")) =~ "36"
    end
  end

  # ⚠️ Ничего здесь не проверяет вёрстку. `Phoenix.LiveViewTest` не считает
  # ширины и не применяет CSS (AGENTS.md, CLAUDE.md §7) — что колонки на
  # широкой сцене реально не рвут строку и не заезжают друг на друга,
  # смотрели живьём в браузере на ~2000px/~1400px/мобильном (отчёт агента).
  # Что тесты МОГУТ закрепить — это структурные допущения, на которых новый
  # CSS (`assets/css/app.css`, `@container` над `.feat-lists`) держится молча
  # и без единого предупреждения, если разметка когда-нибудь изменится:
  #
  #   - `.feats > .feat` и `.skills > .sk-row` — селекторы с прямым потомком.
  #     Обёртка вокруг строки (например, ради ещё одной пометки) погасит
  #     колонки, а любой обычный DOM-тест этого не заметит вовсе.
  #   - `.pb` на широкой сцене — не резиновая сетка, а `grid-template-rows:
  #     repeat(3, auto)` с жёстко зашитыми тремя строками: раскладка STR/DEX/
  #     CON | INT/WIS/CHA верна ровно потому, что характеристик всегда шесть.
  #   - `.spell-list` красится вместе с `.feats`, потому что несёт тот же
  #     класс в разметке, а не отдельными правилами — если класс когда-нибудь
  #     отвяжут, список заклинаний молча вернётся в одну узкую колонку.
  describe "широкая сцена: структурные допущения многоколоночной раскладки" do
    setup %{conn: conn} do
      ruleset = Data.ruleset!(Data.default_version())

      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 13, dex: 15, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "available feat rows are direct children of the list", %{view: view} do
      assert has_element?(view, "#feats-available > .feat")

      # Отрицательный контроль на сам комбинатор `>`: `#feat-lists` — дед,
      # а не родитель (между ними ещё `#feats-available`), и селектор обязан
      # это различать — иначе положительная проверка выше ничего не значит.
      refute has_element?(view, "#feat-lists > .feat")
    end

    test "unavailable feat rows are also direct children of their list", %{view: view} do
      assert has_element?(view, "#feats-blocked > .feat")
    end

    test "skill rows are direct children of the list", %{view: view} do
      view |> element("#skill-add-toggle") |> render_click()
      view |> element("#skill-chip-discipline") |> render_click()

      assert has_element?(view, "#skill-rows > .sk-row")
    end

    test "the spell list carries the feats class it shares layout with", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-sorcerer") |> render_click()
      view |> element("#level-1") |> render_click()

      assert has_element?(view, "#spell-list.feats")
    end

    test "point buy always renders exactly the six abilities the grid assumes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render(element(view, "#point-buy"))
      document = LazyHTML.from_fragment(html)

      # `query/2`, не `filter/2`: `filter/2` проверяет только корневые узлы
      # переданного `LazyHTML`, а строки нужны вложенные (AGENTS.md).
      rows = LazyHTML.query(document, ".pb-row")

      assert Enum.count(rows) == 6
    end
  end

  describe "панель итогов разложена по смыслу" do
    setup %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      %{view: view}
    end

    test "четыре группы, и каждая строка лежит в своей", %{view: view} do
      # Те же группы, что у плашек дельты на карточке класса: величины там
      # ровно те же, и две схемы заставляли бы учить обе (CLAUDE.md §6).
      for group <- ~w(vital attack save skill) do
        assert has_element?(view, "#stat-group-#{group}")
      end

      assert has_element?(view, "#stat-group-vital #stat-hp")
      assert has_element?(view, "#stat-group-attack #stat-base_attack")
      assert has_element?(view, "#stat-group-attack #stat-attacks_per_round")
      assert has_element?(view, "#stat-group-save #stat-fort")
      assert has_element?(view, "#stat-group-save #stat-will")
      assert has_element?(view, "#stat-group-skill #stat-skill_free")

      # «Атак / раунд» больше не соседствует с Fort через такую же линию.
      refute has_element?(view, "#stat-group-attack #stat-fort")
    end

    test "«AC голым» и «AC в шмоте» — один ряд с двумя числами", %{view: view} do
      # Одно число читают только в сравнении с другим, поэтому пара, а не две
      # независимые строки; сноска под панелью объясняет разницу.
      assert has_element?(view, "#stat-ac.srow-pair")
      assert has_element?(view, "#stat-ac #stat-ac_naked")
      assert has_element?(view, "#stat-ac #stat-ac_geared")
    end

    test "разбор числа доезжает до панели, а не живёт только на экране просмотра", %{view: view} do
      # Тот же список термов, что и в карточке экрана просмотра: два места,
      # считающие одну сумму, рано или поздно разойдутся. ⚠ У BAB с задачи 3.16
      # это уже не `title`, а термы поп-апа — потому и сверяется по ним.
      assert render(element(view, "#stat-base_attack")) =~ "Fighter 20 из 41 (полный)"

      # ⚠️ И у сейва тоже не «база»: задача «разбор сейвов по классам» заменила
      # единственный терм «база» термом на класс — той же формы, что у BAB,
      # только со своей меткой прогрессии («высокий»/«низкий», их две, не три).
      assert render(element(view, "#stat-fort")) =~ "Fighter 20 из 41 (высокий)"
    end

    test "«не потрачено» требует действия и читается иначе", %{view: view, conn: conn} do
      # Единственное число панели, которое означает незавершённую работу:
      # у 41-уровневого воина 88 очков лежат нетронутыми.
      assert has_element?(view, "#stat-skill_free[data-attention='todo']")

      # …и видно со свёрнутой мобильной шторки, не открывая её.
      assert has_element?(view, "#sheet-free b[data-attention='todo']")

      # Ноль не мозолит глаза: тратить нечего — и метки нет.
      {:ok, empty, _html} = live(conn, ~p"/")
      refute has_element?(empty, "#stat-skill_free[data-attention]")
      refute has_element?(empty, "#sheet-free b[data-attention]")
    end

    # Задача 3.62 (Dan 20.08.2026, скриншот): «нету АБ, только БАБ. И нету
    # АЦ» — было `~w(hp bab saves free)`, `bab` стал `attack` (несёт AB/BAB
    # через чёрточку — так предложил Dan) и добавилась своя ячейка `ac`.
    test "свёрнутая шторка показывает представителей всех групп, включая AB и AC", %{
      view: view
    } do
      for cell <- ~w(hp ac attack saves free) do
        assert has_element?(view, "#sheet-toggle #sheet-#{cell}")
      end

      # Метка называет оба числа и их порядок (AB — то, что реже совпадает
      # с БАБ и чаще требует сверки с листом персонажа).
      assert has_element?(view, "#sheet-attack", "AB/BAB")
    end

    test "строки про вклад в сейвы нет, пока ядру нечего сказать", %{view: view} do
      refute has_element?(view, "#stat-note-save")
    end

    # Запрос Dan 08.08.2026: игроки шарда думают билдами в этих терминах.
    # ⚠️ У чистого воина ДВА флажка сразу — Fighter входит и в Сагру, и в Адру
    # («Воин», revid 16725), и это самый частый реальный билд, а не краевой случай.
    test "флажки групп классов стоят в шапке панели", %{view: view} do
      assert has_element?(view, "#class-groups #class-group-sagra_warriors")
      assert has_element?(view, "#class-groups #class-group-adra_warriors")

      assert render(element(view, "#class-group-sagra_warriors")) =~ "Воины Сагры"
      assert render(element(view, "#class-group-adra_warriors")) =~ "Воины Адры"
    end

    # ⚠️ Разное качество данных обязано быть видно НА ЭКРАНЕ, а не только в гэпе:
    # правило чистоты Сагры прочитано дословно, у Адры его не сформулировал никто.
    # Флажок Адры помечен допущением, флажок Сагры — нет.
    test "флажок Адры помечен допущением, флажок Сагры нет", %{view: view} do
      assert has_element?(view, "#class-group-adra_warriors[data-assumed='1']")
      refute has_element?(view, "#class-group-sagra_warriors[data-assumed]")

      # ⚠️ И имена классов в пояснении — английские (§4), а имя группы русское:
      # английского имени у группы не существует нигде.
      # ⚠️ «Weapon master», а не «Weapon Master»: имя класса — заголовок страницы
      # Fandom как есть, title-case там не используется, и дорисовывать его было
      # бы выдумкой (CLAUDE.md §3). Проверяется то, что лежит в данных.
      title = render(element(view, "#class-group-sagra_warriors"))
      assert title =~ "Weapon master"
      assert title =~ "Dwarven defender"
    end

    # Порча «не проверять чистоту» валит именно это: один уровень барда сверху —
    # и флажков нет ни одного («любой другой класс в билде нивелирует
    # преимущества», `Воины Сагры`, revid 19232).
    test "один уровень чужого класса убирает оба флажка", %{conn: conn, ruleset: ruleset} do
      mixed =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 40) ++ [:bard],
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(mixed)}")

      refute has_element?(view, "#class-groups")
      refute has_element?(view, "#class-group-sagra_warriors")
      refute has_element?(view, "#class-group-adra_warriors")
    end

    # И пустой билд: секции нет вовсе, а не пустая рамка с ничем внутри.
    test "у пустого билда секции флажков нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#class-groups")
    end

    test "прибавка к сейвам с вещей названа в разборе, а не растворяется", %{view: view} do
      view |> element("#gear-toggle") |> render_click()
      view |> form("#gear-form", %{"saves" => "5"}) |> render_change()

      # Раньше разбор кончался на эпике, и сумма не сходилась с числом рядом.
      assert render(element(view, "#stat-fort")) =~ "вещи"
      assert render(element(view, "#stat-note-save")) =~ "вещи"
    end

    # §3 требует показывать вклад Spellcraft прямо: игроки его не считают,
    # а у чистого заклинателя это восемь пунктов ко всем трём сейвам.
    test "вклад Spellcraft в сейвы виден в панели и в разборе", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(spellcraft_sorcerer(ruleset))}")

      assert render(element(view, "#stat-note-save")) =~ "Spellcraft"
      assert render(element(view, "#stat-will")) =~ "Spellcraft"
    end

    # ⚠️ Потолок +20 общий на вещи и Spellcraft. Подпись, обвиняющая только
    # введённое число, теперь врала бы: срезать может и при вводе меньше капа.
    test "срез общего потолка сейвов называет обе половины", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(spellcraft_sorcerer(ruleset))}")

      view |> element("#gear-toggle") |> render_click()
      view |> form("#gear-form", %{"saves" => "20"}) |> render_change()

      assert has_element?(view, "#stat-fort[data-capped='1']")
      assert render(element(view, "#gear-saves-capped")) =~ "Spellcraft"

      # И разбор по-прежнему сходится с числом рядом: срезанное названо.
      assert render(element(view, "#stat-fort")) =~ "сверх капа"
    end
  end

  describe "SR (сопротивление заклинаниям) — задача 3.45, заход 2" do
    # 🔴 Не «SR 0» — строки нет ВООБЩЕ, тот же критерий, что у `@spell_day`
    # и `@skill_totals`: ноль на 95% билдов без единого уровня монаха был бы
    # шумом (Dan 18.08.2026: «показываем для билдов с 12+ уровнями монаха»).
    test "монах 11 не показывает строку SR вовсе", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(monk_up_to(ruleset, 11))}")

      refute has_element?(view, "#stat-spell_resistance")
    end

    # Порог — ровно там, где ядро выдаёт `Diamond soul` (класс, а не слот):
    # 12 уровней монаха, 22 = 12 + 10.
    test "монах 12 показывает строку в группе «живучесть», рядом с HP и AC", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(monk_up_to(ruleset, 12))}")

      assert has_element?(view, "#stat-group-vital #stat-spell_resistance")

      html = render(element(view, "#stat-spell_resistance"))
      doc = LazyHTML.from_fragment(html)
      visible = doc |> LazyHTML.query(".v") |> LazyHTML.text() |> String.trim()

      # Видимый текст — итоговая величина без знака («22», не «+22»), тем же
      # приёмом, что HP и BAB, а не как модификатор AB/сейвов.
      assert visible == "22"

      # Разбор — списком, тем же приёмом, что у HP/AB/AC/сейвов (поп-ап,
      # `stat_pop/1`): «Diamond soul +22», без имени класса и его уровня —
      # это сознательное решение ядра (задача 3.45, заход 1).
      assert pop_terms(html, "stat-spell_resistance") == [
               %{"label" => "Diamond soul", "value" => "+22"}
             ]
    end

    test "повторные взятия Improved spell resistance складываются с Diamond soul в разборе", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        ruleset
        |> monk_up_to(41)
        |> Build.put_feat(21, :general, :improved_spell_resistance)
        |> Build.put_feat(24, :general, :improved_spell_resistance)
        |> Build.put_feat(27, :general, :improved_spell_resistance)

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      html = render(element(view, "#stat-spell_resistance"))
      doc = LazyHTML.from_fragment(html)
      visible = doc |> LazyHTML.query(".v") |> LazyHTML.text() |> String.trim()

      # 41 + 10 = 51 (Diamond soul) + 3 × 2 = 6 (Improved spell resistance) = 57.
      assert visible == "57"

      assert pop_terms(html, "stat-spell_resistance") == [
               %{"label" => "Diamond soul", "value" => "+51"},
               %{"label" => "Improved spell resistance ×3", "value" => "+6"}
             ]
    end

    # ⚠️ Ворота — уровни МОНАХА, а не владение `Diamond soul`: фит можно
    # объявить с вещи, и тогда у билда без единого уровня монаха ядро честно
    # посчитает `spell_resistance: 10` (источник сам называет это число) —
    # но строку про это Dan не просил, и ей не место на экране воина.
    test "объявленный с вещи Diamond soul у НЕ-монаха строку не открывает", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          gear: Gear.new(feats: [:diamond_soul])
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      refute has_element?(view, "#stat-spell_resistance")
    end

    # SR с предметов не считаем, но у SR вещь не прибавляет, а КОНКУРИРУЕТ
    # (см. `priv/rules/vanilla/feat_spell_resistance.json` → `_gear_decision`),
    # и это надо сказать вслух ровно там, где мы печатаем число.
    test "оговорка про предметы доезжает до панели неточностей", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(monk_up_to(ruleset, 12))}")

      view |> element("#gaps-toggle") |> render_click()

      assert render(element(view, "#gaps-body")) =~ "SR с предметов не считаем"
    end

    # Положительный контроль к тесту выше: у билда без монаха-12+ вопрос
    # не возникает, и оговорка — не «сказано про несуществующий вопрос».
    test "у монаха 11 оговорки про предметы тоже нет", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(monk_up_to(ruleset, 11))}")

      view |> element("#gaps-toggle") |> render_click()

      refute render(element(view, "#gaps-body")) =~ "SR с предметов не считаем"
    end
  end

  describe "характеристики переехали в панель итогов (задача 3.2)" do
    # ⚠️ «Нулевой уровень» здесь — история задачи 3.2 (до неё разбор жил
    # только на отдельном экране создания персонажа); с задачей 3.17 такого
    # экрана не существует вовсе, но контраст «не там, где раньше» остаётся
    # верным и стоит здесь как есть, не как утверждение о текущей архитектуре.
    test "группа характеристик стоит выше «Живучести», а не на отдельном экране создания",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#stat-group-abilities")

      # `~` — «встречается раньше в тех же родителях»: обе группы лежат прямо
      # в `#stat-rows`, поэтому это ровно проверка DOM-порядка, а не догадка.
      assert has_element?(view, "#stat-group-abilities ~ #stat-group-vital")
    end

    # ⚠️ Задача 3.13 (Dan 03.08.2026) перевернула проверку, которая тут стояла
    # раньше: тогда разбор был обязан быть виден БЕЗ наведения, теперь он
    # обязан быть виден только через поп-ап, а без взаимодействия карточка
    # честно показывает только счёт и модификатор. Это не гипотеза, а прямое
    # указание в задаче — и старую формулировку теста стоило перепроверить,
    # прежде чем чинить: она перестала совпадать с текущим решением Dan,
    # а не с ошибкой в реализации.
    test "все шесть характеристик показаны с числом; разбор — не текстом, а в атрибуте поп-апа",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for ability <- ~w(str dex con int wis cha) do
        assert has_element?(view, "#stat-ability-#{ability}")
        assert has_element?(view, "#stat-pop-ability-#{ability}[data-pop-terms]")
      end

      # Видимый текст карточки — счёт и модификатор (8 покупкой, без расы,
      # уровней и вещей на свежем билде даёт STR 8, модификатор -1), а не
      # разбор: строка `.ab-from` со старой версткой пропала совсем.
      html = render(element(view, "#stat-ability-str"))
      doc = LazyHTML.from_fragment(html)
      visible = doc |> LazyHTML.query(".ab-v") |> LazyHTML.text()

      assert visible =~ "8"
      assert visible =~ "-1"
      refute visible =~ "база"
      refute has_element?(view, "#stat-ability-str .ab-from")

      # А сами термы у поп-апа есть — иначе ему нечего было бы показать по
      # наведению/клику; на «голой» характеристике это ровно один терм.
      assert pop_terms(html, "stat-ability-str") == [%{"label" => "база", "value" => "8"}]
    end

    test "правка поинт-бая сразу видна в данных поп-апа", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      before = render(element(view, "#stat-ability-str"))
      view |> element("#point-buy-str-up") |> render_click()
      after_click = render(element(view, "#stat-ability-str"))

      refute before == after_click
      assert pop_terms(before, "stat-ability-str") == [%{"label" => "база", "value" => "8"}]
      assert pop_terms(after_click, "stat-ability-str") == [%{"label" => "база", "value" => "9"}]
    end

    test "раса тоже сразу видна в поп-апе — это тот же каскад, что и поинт-бай", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()

      # Гном (Dwarf на движке) даёт CON +2 — тот факт, что уже проверен
      # в data_test.exs; здесь важно только то, что панель итогов его показывает.
      html = render(element(view, "#stat-ability-con"))
      assert %{"label" => "раса", "value" => "+2"} in pop_terms(html, "stat-ability-con")
    end

    # ⚠️ Тест перевёрнут дважды. Задачей 3.1 гэп «прибавки от фитов»
    # (`ability_bonus_feats_and_class`) стал считаться — заметка исчезла
    # совсем, тест требовал её отсутствия. Задачей 3.8 (04.08.2026,
    # «вычистить пояснительный текст») заметка вернулась, но с ДРУГИМ
    # содержанием: два признания в непосчитанном («расовые и оружейные
    # бонусы Сиалы», «потолок +12 и штраф») раньше стояли прозой в шапке
    # выбора расы и под вводом «Вещей» и оттуда переехали именно сюда
    # (`ability_gap_note/1`) — панель пробелов справа их не показывает вовсе,
    # оба тонут за сотней других «не смоделировано» под усечением
    # `Enum.take/2` (проверено `mix run`, до какой строки оно долистывает).
    # «Заметки нет» больше не факт о ядре в целом, а факт про ОДИН конкретный
    # гэп, поэтому и проверка — по содержимому, а не по существованию узла.
    test "заметки под характеристиками больше нет — оба её гэпа сняты решениями",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/")

      # 🔴 ЗАМЕТКИ НЕТ ВОВСЕ, и это правка 22.08.2026 (задача 3.81). Здесь
      # стоял `note = render(element(view, "#stat-note-abilities"))` и проверки
      # её содержимого; узла больше не существует, потому что `ability_gap_note/1`
      # осталась с одной формой (`{:not_modelled, :ability_bonus_feats_and_class}`),
      # а её ни один рабочий ruleset не производит.
      #
      # Два соседа ушли за один день и оба решением Dan:
      #   * `{:not_modelled, :ability_cap_penalty_interaction}` — задача 3.77
      #     (взаимодействие штрафа с потолком +12 невыразимо в нашей форме
      #     ввода: на характеристику приходится одно число, и оно нетто);
      #   * `{:missing_data, :racial_bonus_progression}` — задача 3.81
      #     («прогрессию делать не будем, данный пробел можно закрыть»).
      #
      # 🔴 Это НЕ значит, что игрок перестал слышать про непосчитанный расовый
      # бонус: у билда ниже 40-го гэп `{:missing_data, {:racial_bonus_level,
      # race}}` приезжает от ядра и печатается в блоке «этот билд». Ушло
      # признание про полноту наших ДАННЫХ, а не про конкретное число —
      # это под тестом в `racial_bonus_test.exs` («решение 3.81 сняло гэп
      # корпуса и не тронуло гэп билда»).
      refute has_element?(view, "#stat-note-abilities")

      # 🔴 Положительный контроль, без которого `refute` выше зеленел бы
      # и у сломанной панели: пропала ЗАМЕТКА, а не блок характеристик, —
      # сам разбор на месте и печатает прибавку по имени.
      build =
        ruleset
        |> fighter_41()
        |> Build.put_feat(21, :general, :great_strength)
        |> Build.put_feat(24, :general, :great_strength)

      {:ok, with_feat, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      html = render(element(with_feat, "#stat-ability-str"))

      assert %{"label" => "Great strength ×2", "value" => "+2"} in pop_terms(
               html,
               "stat-ability-str"
             )
    end

    test "кап +12 с вещей показан плашкой, а не молча обрезан", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#gear-toggle") |> render_click()
      view |> form("#gear-form", %{"ability" => %{"str" => "30"}}) |> render_change()

      assert has_element?(view, "#stat-ability-str .capped")
      assert render(element(view, "#stat-ability-str")) =~ "кап +12"

      # Положительный контроль: без вещей плашки нет вовсе.
      refute has_element?(view, "#stat-ability-dex .capped")
    end

    test "поинт-бай больше не показывает финал и оговорку про нечётность", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html = render(element(view, "#point-buy"))

      refute html =~ "финал"
      refute html =~ "нечётный"
    end
  end

  describe "«из чего собрано» доехало до AB/AC/сейвов/HP (задача 3.6)" do
    test "все семь строк несут разбор в атрибуте поп-апа, а значение видно и без него", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      for key <- ~w(attack_bonus ac_naked ac_geared fort ref will hp) do
        assert has_element?(view, "#stat-pop-#{key}[data-pop-terms]")
      end

      # Видимый текст строки — само число, а не разбор (тот же контракт, что
      # у характеристик в задаче 3.13): наведения/клика `LiveViewTest` не
      # делает, поэтому то, что видно БЕЗ них, и есть то, что видит игрок,
      # ни разу не притронувшийся к панели.
      hp_html = render(element(view, "#stat-hp"))
      doc = LazyHTML.from_fragment(hp_html)
      visible = doc |> LazyHTML.query(".v") |> LazyHTML.text()

      # 410 из хит-дайсов + 41 от бесплатного Toughness (задача 1.9) + 20 от
      # «Духа Сиалы» (задача, волна 12, 09.08.2026) = 471.
      assert visible =~ "471"
      refute visible =~ "Fighter"
    end

    # ⚠️ Задача 3.16 забрала BAB из этого списка — у него теперь свой поп-ап
    # (см. describe ниже). Оставшиеся две строки без термов остаются такими
    # не «потому что до них не дошли», и у каждой своя причина, записанная
    # в `panel_terms/3`: «Атак / раунд» — не сумма слагаемых вовсе, а
    # скилл-поинты разбираются на «потрачено / свободно», что и стоит подписью.
    test "атаки/раунд и скилл-поинты — по-прежнему без поп-апа", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      for key <- ~w(attacks_per_round skill_points skill_free) do
        refute has_element?(view, "#stat-pop-#{key}")
      end

      # Подписи при этом на месте — обе строки объясняют себя, просто не термами.
      assert render(element(view, "#stat-attacks_per_round")) =~ "от BAB 20"
      assert render(element(view, "#stat-skill_points")) =~ "потрачено"
    end

    test "AB называет BAB, характеристику и не несёт пустых термов без вещей", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      terms = pop_terms(render(element(view, "#stat-attack_bonus")), "stat-attack_bonus")
      labels = Enum.map(terms, & &1["label"])

      assert "BAB" in labels
      assert "STR" in labels

      # Положительный контроль: билд без вещей термина «с вещей» не несёт —
      # нулевое слагаемое не появляется вовсе, а не появляется нулём.
      refute "с вещей" in labels
    end

    # ⚠️ Найденный этой задачей баг: раньше подпись AB на экране просмотра
    # безусловно писала «BAB + STR», даже когда Weapon finesse переключает
    # атаку на DEX — врала ровно у тех билдов, ради которых Finesse берут.
    test "Weapon finesse называет DEX в разборе AB, а не зашитый STR", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 16, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :weapon_finesse}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      terms = pop_terms(render(element(view, "#stat-attack_bonus")), "stat-attack_bonus")
      labels = Enum.map(terms, & &1["label"])

      assert %{"label" => "DEX", "value" => "+3"} in terms
      refute "STR" in labels
    end

    # 🔴 Задача 3.22: прибавка от вещей входит В ТЕРМ ХАРАКТЕРИСТИКИ и отдельной
    # строки у AB не имеет — так же, как у сейвов и у «AC в шмоте», которые
    # печатали модификатор с вещами одним термом всегда. Раньше здесь ожидался
    # терм «вещи +2» рядом с голым «STR +0».
    test "прибавка с вещей едет в терме характеристики, отдельной строки нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      before_gear = pop_terms(render(element(view, "#stat-attack_bonus")), "stat-attack_bonus")

      # Предпосылка и положительный контроль: до вещей STR ровно +0 (силы 10).
      assert %{"label" => "STR", "value" => "+0"} in before_gear

      view |> element("#gear-toggle") |> render_click()
      view |> form("#gear-form", %{"ability" => %{"str" => "4"}}) |> render_change()

      terms = pop_terms(render(element(view, "#stat-attack_bonus")), "stat-attack_bonus")

      assert %{"label" => "STR", "value" => "+2"} in terms
      refute Enum.any?(terms, &(&1["label"] in ["вещи", "с вещей"]))
    end

    test "«AC в шмоте» называет каждый ненулевой тип поимённо; «голым» их не несёт вовсе", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      view |> element("#gear-toggle") |> render_click()
      view |> form("#gear-form", %{"ac" => %{"armor" => "8", "shield" => "2"}}) |> render_change()

      geared = pop_terms(render(element(view, "#stat-ac_geared")), "stat-ac_geared")
      assert %{"label" => "Броня", "value" => "+8"} in geared
      assert %{"label" => "Щит", "value" => "+2"} in geared

      # Положительный контроль: «голым» вещи не считает вовсе — ни введённая
      # броня, ни щит в его разборе не появляются.
      naked = pop_terms(render(element(view, "#stat-ac_naked")), "stat-ac_naked")
      refute Enum.any?(naked, &(&1["label"] in ["Броня", "Щит"]))
    end

    # Задача 3.59B (часть 2): `Monk AC bonus` печатал имя фита без слова
    # «мудрость» — тот же приём, что уже есть у AB при Weapon Finesse
    # («от DEX»), у AC его не было ни разу.
    test "Monk AC bonus называет характеристику, от которой считается", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(monk_5_wis_18(ruleset))}")

      terms = pop_terms(render(element(view, "#stat-ac_geared")), "stat-ac_geared")
      assert %{"label" => "Monk AC bonus (WIS)", "value" => "+4"} in terms

      # ⚠️ И положительный контроль: колонка таблицы класса — это НЕ тот же
      # фит, и характеристики не имеет вовсе (её величина — уровень класса,
      # а не мудрость), поэтому у неё пометки быть не должно.
      assert %{"label" => "Monk (класс)", "value" => "+1"} in terms
    end

    # Задача 3.59B (часть 3): монах 5 в кожаном доспехе (+2 AC, база 2) —
    # оба монашеских терма пропадают из «в шмоте», раньше молча. Числа —
    # AC голым 15, AC в шмоте 12 — те же, что в постановке задачи.
    test "пропавший из-за доспеха монашеский терм назван строкой с нулём", %{
      conn: conn,
      ruleset: ruleset
    } do
      %Build{} = base = monk_5_wis_18(ruleset)
      build = %Build{base | gear: Gear.new(worn: %{armor: :leather})}
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert render(element(view, "#stat-ac_naked")) =~ "15"
      assert render(element(view, "#stat-ac_geared")) =~ "12"

      geared = pop_terms(render(element(view, "#stat-ac_geared")), "stat-ac_geared")

      assert %{
               "label" => "Monk AC bonus (WIS) — не работает (надето: Броня)",
               "value" => "0"
             } in geared

      assert %{"label" => "Monk (класс) — не работает (надето: Броня)", "value" => "0"} in geared

      # ⚠️ Положительный контроль: «голым» оба терма живы и ненулевые —
      # пропажа видна ровно там, где она происходит, и не раньше.
      naked = pop_terms(render(element(view, "#stat-ac_naked")), "stat-ac_naked")
      assert %{"label" => "Monk AC bonus (WIS)", "value" => "+4"} in naked
      assert %{"label" => "Monk (класс)", "value" => "+1"} in naked
    end

    # ⚠️ То же правило — и на ЩИТЕ, а не только на доспехе (постановка 3.59B:
    # «проверь оба»). Отдельный билд и отдельный предмет — иначе тест был бы
    # положительным контролем только для одного из двух типов scope.
    test "то же правило работает и на щите, а не только на доспехе", %{
      conn: conn,
      ruleset: ruleset
    } do
      %Build{} = base = monk_5_wis_18(ruleset)
      build = %Build{base | gear: Gear.new(worn: %{shield: :small})}
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      geared = pop_terms(render(element(view, "#stat-ac_geared")), "stat-ac_geared")

      assert %{
               "label" => "Monk AC bonus (WIS) — не работает (надето: Щит)",
               "value" => "0"
             } in geared
    end

    test "упёршийся в дожик-кап +20 назван плашкой у «в шмоте», а не молча срезан", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      cap = ruleset.stat_caps.dodge_ac

      view |> element("#gear-toggle") |> render_click()
      view |> form("#gear-form", %{"ac" => %{"dodge" => to_string(cap + 10)}}) |> render_change()

      assert has_element?(view, "#stat-ac_geared .capped")
      assert render(element(view, "#stat-ac_geared")) =~ "кап +#{cap}"

      # Положительный контроль: «голым» дожика не касается вовсе.
      refute has_element?(view, "#stat-ac_naked .capped")
    end

    test "сейв называет классы, характеристику и Spellcraft — тем же приёмом, что и у навыков", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(spellcraft_sorcerer(ruleset))}")

      for save <- ~w(fort ref will) do
        terms = pop_terms(render(element(view, "#stat-#{save}")), "stat-#{save}")
        labels = Enum.map(terms, & &1["label"])

        # ⚠️ Классовая часть вместо прежней «базы»: у соркерера 40 половина
        # лестницы за окном, и разбор обязан это назвать, а не сложить в одно
        # анонимное число.
        assert Enum.any?(labels, &(&1 =~ "Sorcerer 20 из 40"))
        assert "Spellcraft" in labels
      end
    end

    test "HP называет каждый класс своим хит-дайсом, CON и бесплатный Toughness", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      terms = pop_terms(render(element(view, "#stat-hp")), "stat-hp")

      assert %{"label" => "Fighter 41 (d10)", "value" => "410"} in terms
      assert Enum.any?(terms, &(&1["label"] =~ "CON"))

      # Задача 1.9: фит, который класс выдаёт даром, стоит в разборе своим
      # именем — иначе 471 против 410 выглядит как ошибка расчёта.
      assert %{"label" => "Toughness", "value" => "+41"} in terms

      # Задача, волна 12 (09.08.2026): «Дух Сиалы» — флэт +20, не феат, стоит
      # своей строкой отдельно от Toughness.
      assert %{"label" => "Дух Сиалы", "value" => "+20"} in terms

      sum =
        terms
        |> Enum.map(fn %{"value" => v} -> v |> Integer.parse() |> elem(0) end)
        |> Enum.sum()

      assert sum == 471
    end

    # ⚠️ Здесь стояло «у HP нет поп-апа, когда сам HP посчитать нельзя»
    # на билде с Учеником красного дракона: у него не было хит-дайса, и HP
    # приходило `nil`. Задача 3.37 хит-дайс прочитала — растущим, — и ни один
    # класс обоих ruleset'ов больше не отказывает HP, то есть через LiveView
    # тот путь недостижим вовсе. Само свойство «непосчитанному нечем открывать
    # поп-ап» под тестом остался, но уже там, где ruleset можно подменить
    # (`Summary.hp_terms/2`, `summary_test.exs`).
    #
    # Кейс переехал на то, что эта правка ПРИНЕСЛА: у растущего дайса разбор
    # обязан назвать все дайсы, которые билд прошёл. Одно число рядом с
    # подытогом, на которое тот не делится, читалось бы как ошибка калькулятора.
    test "у растущего хит-дайса в поп-апе лестница дайсов", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:bard, 6) ++ List.duplicate(:red_dragon_disciple, 7)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      terms = pop_terms(render(element(view, "#stat-hp")), "stat-hp")

      assert %{"label" => "Red dragon disciple 7 (d6×3 + d8×2 + d10×2)", "value" => "54"} in terms
      assert %{"label" => "Bard 6 (d6)", "value" => "36"} in terms
    end
  end

  describe "BAB разложен по классам (задача 3.16)" do
    test "разбор едет в поп-апе, а само число видно и без него", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      assert has_element?(view, "#stat-pop-base_attack[data-pop-terms]")

      assert pop_terms(render(element(view, "#stat-base_attack")), "stat-base_attack") == [
               %{"label" => "Fighter 20 из 41 (полный)", "value" => "20"},
               %{"label" => "эпик", "value" => "+11"}
             ]

      # Тот же контракт, что у остальных строк панели: `LiveViewTest` не наводит
      # мышь, поэтому видимый текст — это ровно то, что видит игрок, ни разу
      # не притронувшийся к панели.
      visible =
        render(element(view, "#stat-base_attack"))
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(".v")
        |> LazyHTML.text()

      assert visible =~ "31"
      refute visible =~ "Fighter"
    end

    # 🔴 Главное, чего панель не говорила: у мультикласса часть уровней в BAB
    # не идёт вообще, и разбор обязан назвать их вслух.
    test "класс, взятый после 20-го, стоит в разборе с нулём", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      terms = pop_terms(render(element(view, "#stat-base_attack")), "stat-base_attack")

      assert %{"label" => "Wizard 20 (низкий)", "value" => "10"} in terms
      assert %{"label" => "Fighter 0 из 20 (полный)", "value" => "0"} in terms
      assert %{"label" => "эпик", "value" => "+10"} in terms
      assert length(terms) == 3
    end

    # 🔴 Задача 3.137 (Dan, 29.08.2026, скриншот «Итого»): «похоже вот эту
    # подсказку можно убрать, она между атакой и спасами. В целом у нас
    # и так все подписано откуда и что, в спасах видно все начисления
    # и в АБ/БАБ». Прогон подтвердил довод сильнее вкуса: строка
    # (`Summary.counted_window_note/1`) печаталась почти на любом капнутом
    # билде, включая ОДНОклассовые (воин 40 = BAB 30 — порядку взятия
    # классов там неоткуда взяться), и переставала читаться. Разбор BAB
    # выше и разбор каждого сейва (`сейвы разложены по классам`) и так
    # называют отброшенные уровни поимённо — теста на их содержимое эта
    # правка не касается.
    #
    # ⚠️ Функция-производитель НЕ удалена — её по-прежнему зовёт экран
    # просмотра (`BuildViewLive`), и там та же строка проверяется отдельно
    # (`build_view_live_test.exs`). Здесь проверяется только то, что
    # КОНСТРУКТОР её больше не печатает, даже у билда, на котором раньше
    # печатал.
    test "правило про первые 20 уровней в конструкторе больше не печатается", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      refute has_element?(view, "#stat-note-attack")
    end

    test "у билда внутри окна строки про правило тоже нет", %{conn: conn, ruleset: ruleset} do
      # Положительный контроль: до 20-го уровня отбирать нечего, то есть
      # строки нет и по старой причине (`levels_dropped?` ложно), не только
      # потому, что конструктор перестал её печатать вовсе.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert has_element?(view, "#stat-pop-base_attack")
      refute has_element?(view, "#stat-note-attack")
    end
  end

  describe "сейвы разложены по классам" do
    # 🔴 Ровно то, чего панель не говорила: `Волшебник 20 → Воин 20` показывал
    # у Fort «база 6» и молчал, что шесть — волшебниковы, а двадцать уровней
    # воина не дали ни одному из трёх сейвов ничего.
    test "класс, взятый после 20-го, стоит с нулём в разборе каждого сейва", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:wizard, 20) ++ List.duplicate(:fighter, 20),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert pop_terms(render(element(view, "#stat-fort")), "stat-fort") == [
               %{"label" => "Wizard 20 (низкий)", "value" => "6"},
               %{"label" => "Fighter 0 из 20 (высокий)", "value" => "0"},
               %{"label" => "эпик", "value" => "+10"},
               %{"label" => "CON", "value" => "+0"}
             ]

      assert pop_terms(render(element(view, "#stat-will")), "stat-will") == [
               %{"label" => "Wizard 20 (высокий)", "value" => "12"},
               %{"label" => "Fighter 0 из 20 (низкий)", "value" => "0"},
               %{"label" => "эпик", "value" => "+10"},
               %{"label" => "WIS", "value" => "+0"}
             ]

      # Тот же контракт, что у остальных строк панели: разбор живёт в поп-апе,
      # а само число видно тому, кто мыши не касался.
      visible =
        render(element(view, "#stat-fort"))
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(".v")
        |> LazyHTML.text()

      assert visible =~ "16"
      refute visible =~ "Wizard"
    end

    # ⚠️ Эпический терм у сейвов НЕ равен эпическому терму атаки: у сейвов он
    # растёт на чётных уровнях, у атаки на нечётных, поэтому на капе 41 их
    # разводит на единицу. Проверяется в одном билде и в одной панели — там,
    # где игрок увидел бы оба числа рядом.
    test "на 41-м уровне эпик у сейвов +10, а у BAB +11", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")

      epic = fn key ->
        render(element(view, "#stat-#{key}"))
        |> pop_terms("stat-#{key}")
        |> Enum.find(&(&1["label"] == "эпик"))
      end

      assert epic.("base_attack") == %{"label" => "эпик", "value" => "+11"}

      for save <- ~w(fort ref will) do
        assert epic.(save) == %{"label" => "эпик", "value" => "+10"}, save
      end
    end
  end

  describe "значения навыков в панели итогов (задача 3.4b)" do
    test "билд без вложенных навыков не рисует секцию-призрак", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#stat-group-skills")
    end

    # Положительный контроль к `refute` выше — иначе он мог бы зеленеть
    # просто потому, что секция не рисуется никогда.
    test "вложенный навык рисует секцию со своей строкой", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(elf_cleric_with_spot(ruleset))}")

      assert has_element?(view, "#stat-group-skills")
      assert has_element?(view, "#stat-skill-spot")
    end

    # Дословный повод Dan: большой мод мудрости обязан быть виден в разборе
    # ПОИМЁННО, а не раствориться в одном итоговом числе — «WIS» названа
    # рядом со своим числом, тем же поп-апом (`stat_pop/1`), что уже
    # разбирает характеристики/AB/AC/сейвы/HP (задачи 3.13/3.6).
    test "большой мод мудрости назван в разборе Spot по имени характеристики", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(elf_cleric_with_spot(ruleset))}")

      # WIS 20 → модификатор +5, Elf → +2 расовой склонности к Spot,
      # один купленный ранг: итог 1 + 5 + 2 = 8.
      html = render(element(view, "#stat-skill-spot"))
      terms = pop_terms(html, "stat-skill-spot")

      assert %{"label" => "ранги", "value" => "1"} in terms
      assert %{"label" => "WIS", "value" => "+5"} in terms
      assert %{"label" => "раса", "value" => "+2"} in terms

      # Видимый текст — оба числа канонического формата (CLAUDE.md §3):
      # ранги и итог с модификаторами, а не только одно из них.
      doc = LazyHTML.from_fragment(html)
      visible = doc |> LazyHTML.query(".sk-total") |> LazyHTML.text()
      assert visible =~ "1"
      assert visible =~ "8"
    end

    # Тот же билд с низкой мудростью вместо высокой — разбор обязан назвать
    # другое число, а не одно и то же «WIS» при любом статe: если бы термы
    # были захардкожены мимо `stats.skill_values`, оба билда показали бы
    # один и тот же поп-ап.
    test "разбор реагирует на характеристику, а не печатает одну и ту же строку всегда", %{
      conn: conn,
      ruleset: ruleset
    } do
      low_wis = %{
        elf_cleric_with_spot(ruleset)
        | base_abilities: %{wis: 8, str: 10, dex: 10, con: 10, int: 10, cha: 10}
      }

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(low_wis)}")

      assert %{"label" => "WIS", "value" => "-1"} in pop_terms(
               render(element(view, "#stat-skill-spot")),
               "stat-skill-spot"
             )
    end

    test "кросс-классовый навык помечен ×2, как в колонке прогрессии", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(elf_cleric_with_spot(ruleset))}")

      # Spot не входит в классовые навыки клирика — кросс-классовый билду
      # целиком.
      assert has_element?(view, "#stat-skill-spot[data-cross='1'] .lv-sk-x2")
    end

    # 🔴 ТЕСТ ПЕРЕВЁРНУТ 25.08.2026 (задача 3.95), и это не ослабление, а
    # единственная правда, которую конструктор сегодня может показать.
    #
    # ⚠️ Здесь стояло `assert render(element(view, "#stat-note-skill-spot")) =~
    # "Favored enemy"` — «неучтённый фит назван поимённо СНАРУЖИ поп-апа».
    # Носитель менялся дважды за один день: 3.92 сняла `Skill focus` (его +3
    # теперь считаются), 3.95 сняла `Favored enemy` (решение владельца —
    # описание фита называет и число, и условие точнее нашей фразы).
    #
    # 🔴 Живых записей, способных наполнить `unmodelled_feats` на `siala_41`,
    # не осталось НИ ОДНОЙ, а `BuilderLive` всегда читает `Data.ruleset!()` —
    # то есть подсунуть синтетический ruleset сквозным путём нельзя. Значит
    # блок `#stat-note-skill-*` в конструкторе сегодня не отрисуется ни на
    # одном билде, и утверждать обратное тестом было бы ложью.
    #
    # ⚠️ Сам механизм печати проверяется на уровень ниже и СИНТЕТИЧЕСКОЙ
    # записью — `BuildCalculatorWeb.Builder.SummaryTest`, «непосчитанный фит
    # назван — и значения он не меняет». Здесь остаётся то, что сквозной
    # путь всё же доказывает: значение навыка на месте, а внутрь поп-апа
    # дыра не подмешалась.
    test "оговорки про неучтённый фит нет ни снаружи поп-апа, ни в разборе", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(ranger_with_spot_and_favored_enemy(ruleset))}")

      refute has_element?(view, "#stat-note-skill-spot")

      # Значение навыка при этом на месте и прежнее: 3.95 сняла признание,
      # а не число.
      assert has_element?(view, "#stat-skill-spot")

      terms = pop_terms(render(element(view, "#stat-skill-spot")), "stat-skill-spot")
      refute Enum.any?(terms, &(&1["label"] =~ "Favored enemy"))
    end

    # 🔴 И обратная сторона той же правки, сквозным путём: посчитанный фит
    # стоит ТЕРМОМ внутри поп-апа и оговоркой снаружи НЕ стоит. Два соседних
    # теста на одном экране — иначе «оговорка ушла» и «оговорка сломалась»
    # выглядели бы одинаково.
    test "посчитанный фит стоит термом в разборе, а оговоркой — нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(rogue_with_hide_and_skill_focus(ruleset))}")

      terms = pop_terms(render(element(view, "#stat-skill-hide")), "stat-skill-hide")
      assert %{"label" => "Skill focus", "value" => "+3"} in terms

      refute has_element?(view, "#stat-note-skill-hide")
    end

    # ⚠️ Здесь стояли ДВА теста на общую заметку секции «Без боевой обстановки:
    # освещение, движение и стойку не считаем». **Заметка убрана 20.08.2026
    # решением Dan** («если бы мы это учитывали, это бы явно прописано»), и оба
    # ушли вместе с ней: второй был положительным контролем «а без подверженного
    # навыка заметки нет вовсе» и после удаления проходил бы при любом коде.
    # Само правило не менялось — обстановка не свойство билда и гэпом никогда
    # не была; менялось только то, проговаривает ли панель это вслух.

    # 🔴 Здесь стояло «навык без ключевой характеристики (alchemy) показывает
    # «?», а не молчаливый ноль». **Замер Dan 17.08.2026 (кейс P1) назвал
    # характеристику** — мудрость, — и «?» у навыка в панели итогов больше
    # не производит ни один поставляемый ruleset. Подменить ruleset здесь
    # нечем: LiveView берёт его из `Data.ruleset!/0`, вкомпилированного
    # в приложение.
    #
    # ⚠️ Кейс перевёрнут в положительный, а печать «?» проверяется слоем ниже,
    # где ruleset — аргумент: `Summary.skill_rows/3` (`summary_test.exs`)
    # и `Export.text/3`. Здесь остаётся то, что проверяется только отсюда:
    # у строки навыка нет пометки «неизвестно», то есть панель печатает число.
    test "навык шарда (alchemy) показывает число: характеристика названа замером", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:harper_scout, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 14, cha: 10},
          skills: %{1 => %{alchemy: 4}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      refute has_element?(view, "#stat-skill-alchemy .sk-total[data-unknown='1']")

      # 4 ранга и значение 6 (мудрость +2) — оба числа в строке, как у любого
      # другого навыка.
      row = render(element(view, "#stat-skill-alchemy"))

      assert row =~ "4"
      assert row =~ "(6)"
    end

    # Продуктовое решение записано явно, а не только в HANDOFF: на телефоне
    # шторка в свёрнутом виде остаётся тем же набором представителей групп
    # (HP/AC/AB·BAB/сейвы/свободно — задача 3.62 добавила `ac` и объединила
    # `bab` с AB в `attack`), что и раньше — конкретные значения навыков туда
    # не добавлены. Разворачивание доступно (см. тест выше «вложенный навык
    # рисует секцию»), просто не задваивает то, что уже показывает
    # «Свободно», и не выбирает «самый интересный» навык за игрока —
    # субъективный выбор, честно посчитать который не может никто.
    test "мобильная шторка в свёрнутом виде не растёт от навыков", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(elf_cleric_with_spot(ruleset))}")

      for cell <- ~w(hp ac attack saves free) do
        assert has_element?(view, "#sheet-toggle #sheet-#{cell}")
      end

      refute has_element?(view, "#sheet-toggle #sheet-spot")
    end
  end

  describe "ghost-предпросмотр у строк навыков (волна 10, AGENT_QUEUE §7)" do
    # Долг задачи 3.4b: «Дельта при наведении на карточку класса подсвечивает
    # изменяющиеся строки панели, но у навыков этого нет: `preview_stats`
    # считается для билда целиком, а не по навыкам». `preview` в сокете уже
    # был ПОЛНЫМ `Rules.compute/2` кандидата (тем же, что красит HP/AB/AC),
    # не хватало только чтения `skill_values` из него — ни одного лишнего
    # пересчёта эта секция не стоит.
    #
    # ⚠️ Через `render_hook/3`, а не `render_click` по карточке — та же
    # причина, что у остальных тестов превью в этом файле (баг 1.11): превью
    # висит на отдельной шине `#preview-bus`, а не на самой карточке.

    test "наведение на класс сдвигает значение навыка через классовую способность", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(harper_lore_build(ruleset))}")

      # Билд занимает уровни 1-2, третий ещё не выбран — переходим на него,
      # ничего не выбирая, ровно как это делает наведение мышью на карточку.
      view |> element("#level-3") |> render_click()

      # Положительный контроль: без наведения строка обычная. Без этого
      # `data-changed` ниже мог бы стрелять всегда, а не от превью.
      refute has_element?(view, "#stat-skill-lore[data-changed]")

      render_hook(view, "preview", %{"kind" => "class", "id" => "harper_scout"})

      # 2 уровня Арфиста уже дают Bardic Knowledge +2 к Lore (`class_bonus`,
      # правило `class_level_bonuses` в `siala_41/skills.json`: бонус равен
      # уровню класса начиная со 2-го), третий уровень поднимет её к +3 —
      # значение растёт на +1, хотя ни один ранг не поменялся.
      assert has_element?(view, "#stat-skill-lore[data-changed='1']")
      refute has_element?(view, "#stat-skill-lore[data-down]")
      assert has_element?(view, "#stat-skill-lore .ghost", "+1")
    end

    # Контраст к тесту выше — тот же билд, тот же уровень, другой кандидат.
    # Ghost не «загорается всегда, раз идёт превью», а действительно читает
    # разность: класс, не касающийся Lore, не подсвечивает его строку.
    test "наведение на класс, не задевающий навык, не подсвечивает его строку", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(harper_lore_build(ruleset))}")
      view |> element("#level-3") |> render_click()

      render_hook(view, "preview", %{"kind" => "class", "id" => "fighter"})

      refute has_element?(view, "#stat-skill-lore[data-changed]")
    end

    test "снятие наведения возвращает строку в обычное состояние", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(harper_lore_build(ruleset))}")
      view |> element("#level-3") |> render_click()

      render_hook(view, "preview", %{"kind" => "class", "id" => "harper_scout"})
      assert has_element?(view, "#stat-skill-lore[data-changed='1']")

      render_hook(view, "clear_preview", %{})
      refute has_element?(view, "#stat-skill-lore[data-changed]")
    end

    # Наведение на расу — тоже одна из трёх форм превью (`{:race, id}`), и
    # она двигает значение навыка иначе: не через классовую способность,
    # а через расовую склонность (`race_bonus`, `vanilla/races.json`).
    # Уход от Эльфа теряет его +2 Spot — ghost обязан уйти в минус.
    test "наведение на расу сдвигает значение навыка — теряется склонность", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(elf_cleric_with_spot(ruleset))}")

      render_hook(view, "preview", %{"kind" => "race", "id" => "human"})

      assert has_element?(view, "#stat-skill-spot[data-changed='1'][data-down='1']")
      assert has_element?(view, "#stat-skill-spot .ghost", "-2")
    end

    # Дословный повод Dan (AGENT_QUEUE §3.4b): «большой мод мудрости даст
    # много спота» — раньше это было видно только ПОСЛЕ покупки прибавки,
    # теперь то же самое видно ДО неё, наведением на карточку «+1 к WIS»
    # (`{:increase, id}` — третья форма превью, наравне с классом и расой).
    test "наведение на прибавку к характеристике сдвигает значение навыка", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(elf_cleric_odd_wis(ruleset))}")

      view |> element("#level-4") |> render_click()
      render_hook(view, "preview", %{"kind" => "increase", "id" => "wis"})

      # WIS 19 → 20: модификатор +4 → +5, Spot растёт вместе с ним.
      assert has_element?(view, "#stat-skill-spot[data-changed='1']")
      refute has_element?(view, "#stat-skill-spot[data-down]")
      assert has_element?(view, "#stat-skill-spot .ghost", "+1")
    end
  end

  describe "два вида «не выбрано» в колонке прогрессии" do
    setup %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      %{view: view}
    end

    test "у фита и у прибавки к стату разные метки, а курсив общий", %{view: view} do
      # Янтарь закреплён за фитами, за статом — стальной; курсив у обоих,
      # именно он значит «не выбрано» (CLAUDE.md §6). Раньше оба были янтарными
      # и на 41 строке сливались в один столбик «чего-то не хватает».
      assert has_element?(view, "#level-1 .lv-feat[data-todo='feat']")
      refute has_element?(view, "#level-1 .lv-feat[data-todo='abil']")

      assert has_element?(view, "#level-4 .lv-feat[data-abil='1'][data-todo='abil']")
      refute has_element?(view, "#level-4 .lv-feat[data-abil='1'][data-todo='feat']")
    end

    test "выбранная характеристика красится своим оттенком", %{view: view} do
      view |> element("#level-4") |> render_click()
      view |> element("#increase-card-str") |> render_click()

      row = render(element(view, "#level-4 .lv-feat[data-abil='1']"))

      # STR — 4°, из таблицы Palette; узор из одного-двух цветов отвечает
      # на «куда качали» раньше, чем глаз доберётся до подписей.
      assert row =~ "--h: 4"
      refute row =~ "data-todo"
    end

    # Престиж строка лестницы носит СВОЙ атрибут, а не общий `data-prc`:
    # глобальное `[data-prc="1"] { --cls-s: var(--prc-s) }` подменяет переменные
    # всему поддереву, а оттенки характеристик едут по той же машинерии
    # `hsl(var(--h) var(--cls-s) var(--cls-l))`. Замером до правки: `▲ STR 15`
    # на уровне престиж-класса красился `rgb(169,101,96)` вместо `rgb(151,60,53)`
    # (светлая тема; в тёмной `rgb(205,156,152)` вместо `rgb(206,107,100)`), а на
    # уровнях Мастера оружия сливался с собственной полосой класса
    # `rgb(169,115,96)`. То же имя и по той же причине носит строка гида
    # экрана просмотра (`build_view_live_test.exs`).
    #
    # ⚠️ Здесь стояло «цвет тестом не проверить, имя атрибута — можно, и оно
    # и есть то, что чинилось». Первая половина верна только про сами `rgb(...)`:
    # ПРИЧИНА проверяется без браузера, инвариантом «`data-prc` не содержит
    # чужого `--h`» — тест «ни один `data-prc` не накрывает чужой оттенок» ниже.
    # Этот же остаётся: он про конкретное имя, тот — про правило.
    test "престиж-уровень не подменяет переменные всей строке", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(fighter_then_champion_of_torm(ruleset))}")

      assert ruleset.classes[:champion_of_torm].prestige?
      refute ruleset.classes[:fighter].prestige?

      assert has_element?(view, "#level-12[data-class-prc='1']")
      refute has_element?(view, "#level-12[data-prc='1']")

      # Положительный контроль к обоим `refute`: у базового класса своего
      # атрибута нет вовсе, а не «есть с другим значением», — то есть селектор
      # выше ловит именно престиж, а не любую строку лестницы.
      refute has_element?(view, "#level-1[data-class-prc='1']")
      refute has_element?(view, "#level-1[data-prc='1']")

      # Приглушение никуда не делось — оно осталось на полосе класса, и это
      # видно по тому, что строка вообще несёт свой оттенок: `--h` у неё
      # престижного класса, а не пустой.
      assert has_element?(
               view,
               "#level-12[style*='--h: #{BuildCalculatorWeb.Builder.Palette.hue(:champion_of_torm)}']"
             )

      # Прибавка к характеристике на престиж-уровне — та же строка, что и на
      # базовом: свой оттенок из `Palette`, и ничего в разметке про престиж.
      row = render(element(view, "#level-12 .lv-feat[data-abil='1']"))
      assert row =~ "--h: #{BuildCalculatorWeb.Builder.Palette.ability_hue(:str)}"
      refute row =~ "data-prc"
      refute row =~ "data-class-prc"
    end

    # ⚠️ Тот же атрибут стоит и на шапке `#level-0` (раса/мировоззрение/статы):
    # она несёт ту же `.lv-band`, и общий `data-prc` там подменял бы переменные
    # трём строкам характеристик под заголовком.
    test "шапка создания персонажа носит тот же атрибут", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(champion_of_torm_first(ruleset))}")

      assert has_element?(view, "#level-0[data-class-prc='1']")
      refute has_element?(view, "#level-0[data-prc='1']")

      # Положительный контроль: у билда без престижа на первом уровне атрибута
      # нет ни под одним из двух имён.
      {:ok, plain, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      refute has_element?(plain, "#level-0[data-class-prc='1']")
      refute has_element?(plain, "#level-0[data-prc='1']")
    end

    # ⚠️ Долг §7 AGENT_QUEUE.md, «шестая пятёрка». Здесь и в двух соседних тестах
    # раньше стояло «цвет тестом не проверить, имя атрибута — можно», и это было
    # верно только про сам цвет: ПРИЧИНА обоих цветовых багов (лестница
    # конструктора, гид экрана просмотра) — структурная, и она проверяется без
    # браузера.
    #
    # Правило `[data-prc="1"] { --cls-s: var(--prc-s); --cls-l: var(--prc-l) }`
    # подменяет переменные ВСЕМУ поддереву. Значит элемент с этим атрибутом
    # не имеет права содержать другого потребителя `--h`: у того подменятся
    # насыщенность и светлота, а его собственный оттенок останется — ровно так
    # `▲ STR` на престиж-уровне выцветал до `rgb(169,101,96)` вместо
    # `rgb(151,60,53)`.
    #
    # Инвариант общий, а не про `data-abil`: он поймает и следующего потребителя
    # `--h`, которого ещё не завели. Что этим тестом НЕ проверяется — сами
    # `rgb(...)`: сойдутся ли правила в задуманный цвет, видно только в браузере
    # (замер лежит в отчётах задач и в комментариях `app.css`).
    test "ни один `data-prc` не накрывает чужой оттенок", %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(fighter_then_champion_of_torm(ruleset))}")

      document = view |> render() |> LazyHTML.from_fragment()

      leaked = LazyHTML.query(document, ~s([data-prc] [style*="--h"]))

      assert Enum.count(leaked) == 0,
             """
             Элемент с `data-prc` содержит вложенный `--h`: правило подменит
             ему `--cls-s`/`--cls-l`, и оттенок поедет. Атрибут на контейнере
             обязан называться `data-class-prc`, а приглушение — стоять точечно
             у полосы класса (см. `.lv-band` в app.css).

             #{inspect(leaked)}
             """

      # ⚠️ Положительный контроль, без которого `assert … == 0` зеленел бы и от
      # пустой страницы: конструкция «атрибут на контейнере, чужой оттенок
      # внутри» в разметке ЕСТЬ — просто под своим именем, где она безвредна.
      assert Enum.count(LazyHTML.query(document, ~s([data-class-prc] [style*="--h"]))) > 0

      # И второй контроль: сам селектор `[data-prc]` на этой странице что-то
      # находит, то есть `refute` выше не про отсутствие атрибута вовсе.
      assert Enum.count(LazyHTML.query(document, "[data-prc]")) > 0
    end
  end

  describe "the order of the class cards" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "available first, then the locked ones, both alphabetical", %{view: view} do
      # `~` is "a later sibling of": Cleric before Fighter, Arcane archer before
      # Assassin. Both groups are children of the same grid.
      assert has_element?(view, "#class-card-cleric ~ #class-card-fighter")
      refute has_element?(view, "#class-card-fighter ~ #class-card-cleric")
      assert has_element?(view, "#class-card-arcane_archer ~ #class-card-assassin")
    end

    test "a divider separates the groups and the locked half sits after it", %{view: view} do
      assert has_element?(view, "#class-cards-divider")
      # Arcane archer needs a race and a BAB nobody has at level 1.
      assert has_element?(view, "#class-cards-divider ~ #class-card-arcane_archer")
      # Nothing takeable is stranded below the divider.
      refute has_element?(view, "#class-cards-divider ~ #class-card-fighter")
      refute has_element?(view, "#class-cards-divider ~ #class-card-wizard")
    end

    test "the locked half is shown with its reason rather than hidden", %{view: view} do
      # ⚠️ Раньше здесь стояла ещё проверка текста-пояснения над сеткой
      # («…с причиной, а не спрятаны») — задача 3.8 (04.08.2026) убрала его:
      # это было объяснение НАШЕГО решения показывать карточки так, а не
      # игровой факт (CLAUDE.md §6), и оно дублировало ровно то, что каждая
      # запертая карточка и так печатает сама. Название теста не соврало —
      # поведение проверяет вторая строка: карточка несёт узел с причиной
      # и глифом замка, а не просто существует.
      assert has_element?(view, "#class-lock-arcane_archer")
      assert render(element(view, "#class-lock-arcane_archer")) =~ "🔒"
    end
  end

  describe "gear" do
    setup %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      view |> element("#gear-toggle") |> render_click()
      %{view: view}
    end

    test "the fields come from the ruleset, not from the markup", %{
      view: view,
      ruleset: ruleset
    } do
      assert has_element?(view, "#gear-body")

      for ability <- ruleset.abilities do
        assert has_element?(view, "#gear-ability-input-#{ability}")
      end

      for type <- ruleset.gear.ac_types do
        assert has_element?(view, "#gear-ac-input-#{type}")
      end

      assert has_element?(view, "#gear-saves-input")
      # The ceiling is quoted from the data, never written in the template.
      assert render(element(view, "#gear-form")) =~ "+#{ruleset.gear.ability_bonus_cap}"
    end

    # Потолок есть у одного типа AC, «уклонения» (решение Dan 03.08.2026).
    # Срез обязан быть назван: молча уменьшенное число читается как поломка
    # калькулятора, а не как правило шарда.
    test "срезанный dodge называет себя, а поле ввода не переписывается", %{
      view: view,
      ruleset: ruleset
    } do
      cap = ruleset.stat_caps.dodge_ac
      typed = cap + 5

      refute has_element?(view, "#gear-ac-capped")

      view |> form("#gear-form", %{"ac" => %{"dodge" => "#{typed}"}}) |> render_change()

      assert render(element(view, "#gear-ac-capped-dodge")) =~ "+#{cap}"

      # ⚠️ Введённое число остаётся в поле: подстановка срезанного на его место
      # означала бы, что интерфейс молча правит набранное игроком.
      assert render(element(view, "#gear-ac-input-dodge")) =~ ~s(value="#{typed}")
    end

    # Положительный контроль: тот же перебор потолка типом, у которого потолка
    # нет, не даёт ни пометки, ни среза.
    test "у типа без потолка то же число проходит целиком", %{view: view, ruleset: ruleset} do
      typed = ruleset.stat_caps.dodge_ac + 5

      view |> form("#gear-form", %{"ac" => %{"armor" => "#{typed}"}}) |> render_change()

      refute has_element?(view, "#gear-ac-capped")
      assert render(element(view, "#gear-ac-total")) =~ "#{typed}"
    end

    # 🔴 Вторая причина, по которой введённое число может не доехать до итога
    # (задачи 3.39 и 3.91): сиальский щитовой бонус не складывается с вписанным
    # бонусом щита, а перекрывает его. Молча съеденное число читается как
    # поломка ровно так же, как молча срезанное.
    #
    # ⚠️ Здесь стоял ВОИН с `Armor skin` и вписанным природным AC — при правиле
    # «максимум для всего собственного» строка появлялась и на нём. Задача 3.91
    # сузила правило до одного вида прибавки (расовый щитовой Карлика и его
    # оружейный близнец), и билд пришлось сменить на тот, где правило живёт.
    # ⚠️ Оружие в руках — не декорация: расовый бонус включается им (задача
    # 3.36), без оружия мерялась бы пустота.
    test "проигравший максимуму тип называет себя, а поле не переписывается", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Карлик (Gnome) 41 чистым воином — сагровик, расовый щитовой +9.
      %Build{} = base = fighter_41(ruleset)

      build = %Build{
        base
        | race: :gnome,
          alignment: :lawful_good,
          gear: Gear.new(weapon: :handaxe, feats: [:siala_axe_proficiency])
      }

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#gear-toggle") |> render_click()

      refute has_element?(view, "#gear-ac-superseded")

      view |> form("#gear-form", %{"ac" => %{"shield" => "4"}}) |> render_change()

      assert has_element?(view, "#gear-ac-superseded-shield")

      # ⚠️ Введённое остаётся в поле — интерфейс не правит набранное игроком.
      assert render(element(view, "#gear-ac-input-shield")) =~ ~s(value="4")

      # ⚠️ И положительный контроль на само правило: вписанные 12 больше своих
      # 9, значит выигрывают они и строка исчезает.
      view |> form("#gear-form", %{"ac" => %{"shield" => "12"}}) |> render_change()

      refute has_element?(view, "#gear-ac-superseded")

      # 🔴 И вторая половина правки 3.91, на том же экране: тип, где своя
      # прибавка СКЛАДЫВАЕТСЯ с вписанной, строки не печатает вовсе — иначе
      # игрок читал бы «перебито» там, где ничего не перебито.
      view
      |> form("#gear-form", %{"ac" => %{"natural" => "1", "shield" => "0"}})
      |> render_change()

      refute has_element?(view, "#gear-ac-superseded")
    end

    # 471 = 410 из хит-дайсов + 41 от бесплатного Toughness (задача 1.9) + 20
    # от «Духа Сиалы» (задача, волна 12, 09.08.2026). Прибавка с вещей ни на
    # то, ни на другое не влияет — оба флэт-слагаемых считаются за уровни/
    # владение, а не за CON.
    test "+12 CON becomes +6 on every level: 471 HP → 717", %{view: view} do
      assert render(element(view, "#stat-hp")) =~ "471"

      view |> form("#gear-form", %{"ability" => %{"con" => "12"}}) |> render_change()

      # +12 CON is +6 to the modifier, which is +6 hit points on each of 41
      # levels — the +246 CLAUDE.md §6 names. This is the whole point of the block.
      assert render(element(view, "#stat-hp")) =~ "717"

      cascade = render(element(view, "#gear-cascade-hp"))
      assert cascade =~ "471"
      assert cascade =~ "717"
      assert cascade =~ "+246"
    end

    test "the cascade reaches attack and the saves too", %{view: view} do
      view
      |> form("#gear-form", %{"ability" => %{"str" => "12", "con" => "12"}})
      |> render_change()

      assert has_element?(view, "#gear-cascade-ab")
      assert render(element(view, "#gear-cascade-fort")) =~ "+6"
    end

    # 🔴 Задача 3.41: доспех и щит выбираются из списка, а не вводятся числом.
    # Список — из ruleset'а, ни одной строки в разметке.
    test "надетое выбирается из списка, и список приходит из данных", %{
      view: view,
      ruleset: ruleset
    } do
      for category <- ruleset.gear.worn do
        assert has_element?(view, "#gear-worn-input-#{category.id}")

        for item <- category.items do
          assert has_element?(view, "#gear-worn-#{category.id}-#{item.id}")
        end
      end

      # Строка предмета называет все его величины — база, предел ловкости и
      # штраф к навыкам (задача 3.42), — потому что каждая меняет числа и
      # каждая взята из источника.
      assert render(element(view, "#gear-worn-armor-full_plate")) =~ "+8"
      assert render(element(view, "#gear-worn-armor-full_plate")) =~ "+1"
      assert render(element(view, "#gear-worn-armor-full_plate")) =~ "-8"

      # ⚠️ У щита штраф решает больше базы, и строка обязана это показывать:
      # башенный даёт +3 к AC и отнимает 10 у шести навыков.
      assert render(element(view, "#gear-worn-shield-tower")) =~ "-10"

      # Ноль не печатаем — как и везде: у кожаного строка про навыки пустая.
      refute render(element(view, "#gear-worn-armor-leather")) =~ "навыки"
    end

    # 🔴 Задача 3.43: недоступное не прячется, а называет причину, и записанное
    # нелегальное остаётся в билде строкой — молча отобранное читается как
    # поломка калькулятора.
    test "Карлику башенный щит показан с причиной, а записанный назван строкой", %{
      conn: conn,
      ruleset: ruleset
    } do
      %Build{} = base = fighter_41(ruleset)

      build = %Build{
        base
        | race: :gnome,
          gear: Gear.new(worn: %{shield: :tower})
      }

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#gear-toggle") |> render_click()

      # В списке он есть — с причиной, а не вычеркнут (CLAUDE.md §6).
      assert render(element(view, "#gear-worn-shield-tower")) =~ "Карлик"

      # А записанный — отдельной строкой, которая говорит, что в расчёт он
      # не идёт. Без неё +3 AC просто не появились бы, и это выглядело бы багом.
      assert render(element(view, "#gear-worn-illegal-shield-tower")) =~ "в расчёт не идёт"

      # ⚠️ Отрицательный контроль: у среднего размера ни причины, ни строки.
      {:ok, human, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(%Build{build | race: :human})}")

      human |> element("#gear-toggle") |> render_click()

      refute render(element(human, "#gear-worn-shield-tower")) =~ "не носит"
      refute has_element?(human, "#gear-worn-illegal-shield-tower")
    end

    test "выбранные латы дают базу и режут ловкость к AC, назвав и то и другое", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Воин 41 с DEX 18 (+4): голым AC 14.
      %Build{} = base = fighter_41(ruleset)

      build = %Build{
        base
        | base_abilities: Map.put(base.base_abilities, :dex, 18)
      }

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#gear-toggle") |> render_click()

      refute has_element?(view, "#gear-ac-dex-capped")
      assert render(element(view, "#stat-ac_geared")) =~ "14"

      view |> form("#gear-form", %{"worn" => %{"armor" => "full_plate"}}) |> render_change()

      # 10 базы + 1 ловкости (вместо 4) + 8 базы лат.
      assert render(element(view, "#stat-ac_geared")) =~ "19"

      # ⚠️ Срез назван, и назван вместе с границей: рефлекс и атака ловкость
      # считают целиком, и без этой половины игрок решит, что мы её занизили.
      capped = render(element(view, "#gear-ac-dex-capped"))
      assert capped =~ "+1"
      assert capped =~ "Рефлекс"

      # ⚠️ И положительный контроль тому, что срезан ОДИН терм: рефлекс воина 41
      # (+6 таблицы и +10 эпика) с ПОЛНОЙ ловкостью +4, а не с обрезанной.
      assert render(element(view, "#stat-ref")) =~ "+20"
      assert render(element(view, "#stat-pop-ref")) =~ "DEX"
    end

    # 🔴 Задача 3.42, сквозной путь игрока: выбрал доспех и щит — значение
    # Скрытности на экране изменилось, и разбор рядом называет почему.
    test "выбранные латы со щитом отнимают у Скрытности, и разбор это называет", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} =
        live(conn, ~p"/?b=#{Encoding.encode(rogue_with_hide_and_skill_focus(ruleset))}")

      # Вор 5 с DEX 16 (+3), 4 ранга Скрытности и Skill focus (Hide):
      # 4 + 3 + 3 = 10.
      # ⚠️ Здесь стояло 7 и −11: `Skill focus` не считался до задачи 3.92.
      # Штраф брони от этого не изменился ни на очко — сдвинулась база.
      assert render(element(view, "#stat-skill-hide")) =~ "10"

      view |> element("#gear-toggle") |> render_click()

      view
      |> form("#gear-form", %{"worn" => %{"armor" => "full_plate", "shield" => "tower"}})
      |> render_change()

      # 4 + 3 + 3 − 18 = −8, и штраф назван термом, а не растворён в итоге.
      assert render(element(view, "#stat-skill-hide")) =~ "-8"

      terms = pop_terms(render(element(view, "#stat-skill-hide")), "stat-skill-hide")
      assert %{"label" => "штраф брони", "value" => "-18"} in terms
    end

    # ⚠️ Строка «вписанное не доехало» обязана назвать базу, когда предмет
    # выбран: база складывается всегда, то есть число всё-таки выросло, и без
    # второй половины подпись противоречила бы итогу на экране.
    test "проигравший максимуму тип называет базу выбранного предмета", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Карлик 40 воином с коротким мечом — своё щитовое 18 (раса 9 + оружие 9).
      #
      # ⚠️ Меч КОРОТКИЙ, а не катана (задача 3.43): катана среднего размера, то
      # есть для малой расы двуручна, и щит рядом с ней не надевается вовсе —
      # проверять было бы нечего. Группа владения та же, число то же.
      %Build{} = base = fighter_41(ruleset)

      build = %Build{
        base
        | race: :gnome,
          levels: List.duplicate(:fighter, 40),
          gear: Gear.new(weapon: :shortsword, feats: [:siala_blade_proficiency])
      }

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#gear-toggle") |> render_click()

      view
      |> form("#gear-form", %{"ac" => %{"shield" => "4"}, "worn" => %{"shield" => "large"}})
      |> render_change()

      line = render(element(view, "#gear-ac-superseded-shield"))
      assert line =~ "в расчёт идёт больший"
      assert line =~ "+2"

      # 10 базы + 18 своего + 2 базы среднего щита. ⚠️ Было 31 (с +1 размера
      # Карлика) до задачи 3.143 (30.08.2026): Small stature стал
      # not_modelled — цитата в разметке была обрезана перед условием
      # «когда противник крупнее персонажа».
      assert render(element(view, "#stat-ac_geared")) =~ "30"
    end

    # ⚠️ «Одет» и «вписал число» — с задачи 3.41 разные утверждения, и второе
    # больше не годится как ответ на первое: латы без единой вписанной цифры
    # дают +8.
    #
    # ⚠️ Мест, где этот вопрос задаётся, было ДВА: свёрнутая шапка «Вещей»
    # и подпись под AC («предметов со статами (армори) пока нет»). Подпись
    # убрана 20.08.2026 решением Dan, вместе с ней ушли две строки этого теста.
    # Утверждение теста не ослабло: его доказывают и шапка, называющая предмет
    # по имени, и само число, выросшее на базу лат.
    test "выбранный предмет без единого числа считается надетым", %{view: view} do
      assert render(element(view, "#gear-summary")) =~ "не задано"

      view |> form("#gear-form", %{"worn" => %{"armor" => "full_plate"}}) |> render_change()

      # Свёрнутая шапка называет предмет по имени, а не числом.
      assert render(element(view, "#gear-summary")) =~ "Full plate"
      refute render(element(view, "#gear-summary")) =~ "не задано"

      # И само число выросло на базу лат: воин 41 с DEX 10 — 10 голым, 18 в шмоте.
      assert render(element(view, "#gear-ac-total")) =~ "18"
    end

    test "AC is broken down into base, DEX and what the gear adds", %{
      view: view,
      ruleset: ruleset
    } do
      view
      |> form("#gear-form", %{"ac" => %{"armor" => "8", "deflection" => "5"}})
      |> render_change()

      line = render(element(view, "#gear-ac-total"))

      assert line =~ "#{ruleset.base_ac} базовых"
      assert line =~ "13 с вещей"
      # 10 base + 0 DEX + 13 = 23, and the panel above agrees.
      assert line =~ "23"
      assert render(element(view, "#stat-ac_geared")) =~ "23"
    end

    # 🔴 Задача 3.59B (часть 1), живой случай: Dan прислал ссылку на свой билд
    # и принял «+8 своих» за монашескую колонку — а это оказался Кувырок, та
    # же арифметика («+1 за каждые 5»), другой источник. Билд нарочно БЕЗ
    # единого уровня монаха: если бы строка по-прежнему печатала одно слитое
    # число, тест бы этого не заметил.
    test "«своих» в строке каскада называет источник, а не одно слитое число", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_with_tumble(ruleset))}")
      view |> element("#gear-toggle") |> render_click()

      line = render(element(view, "#gear-ac-total"))

      assert line =~ "Tumble"
      refute line =~ "своих"
      refute line =~ "Monk"

      # И положительный контроль на форму: строка по-прежнему сходится со
      # своим итогом (10 база + 0 DEX + 1 Tumble = 11).
      assert line =~ "11"
      assert render(element(view, "#stat-ac_geared")) =~ "11"
    end

    # И когда оба источника ЖИВЫ одновременно (монах без доспеха, с рангами
    # Кувырка) — строка называет все три термами, а не сваливает их в одну
    # сумму. Ровно то различение, которого не было до задачи 3.59B.
    test "«своих» перечисляет несколько источников разом, а не сливает их", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(monk_with_tumble(ruleset))}")
      view |> element("#gear-toggle") |> render_click()

      line = render(element(view, "#gear-ac-total"))

      assert line =~ "Monk AC bonus (WIS)"
      assert line =~ "Monk (класс)"
      assert line =~ "Tumble"
      refute line =~ "своих"
    end

    test "the summary of the collapsed block says what was typed", %{view: view} do
      assert render(element(view, "#gear-summary")) =~ "не задано"

      view
      |> form("#gear-form", %{"ability" => %{"con" => "12"}, "saves" => "5"})
      |> render_change()

      summary = render(element(view, "#gear-summary"))
      assert summary =~ "CON +12"

      # Задача 3.137: «сейвы» → «спасы» (CLAUDE.md §4, слово аудитории Сиалы).
      assert summary =~ "спасы +5"
    end

    # ⚠️ Раньше форма делала `max(0)`: введённый минус превращался в ноль без
    # единого слова, и билд считался не тот, что ввели. Штрафы в игре есть —
    # Fandom «Ability cap» (revid 68173) описывает именно «STR снижена на −2».
    test "a CON penalty runs the same cascade the other way: 471 HP → 389", %{view: view} do
      view |> form("#gear-form", %{"ability" => %{"con" => "-4"}}) |> render_change()

      # −4 CON это −2 к модификатору, то есть −2 HP на каждом из 41 уровня.
      assert render(element(view, "#stat-hp")) =~ "389"

      cascade = render(element(view, "#gear-cascade-hp"))
      assert cascade =~ "471"
      assert cascade =~ "389"
      assert cascade =~ "-82"
    end

    test "a STR penalty reaches the attack bonus", %{view: view} do
      before = render(element(view, "#stat-attack_bonus"))

      view |> form("#gear-form", %{"ability" => %{"str" => "-4"}}) |> render_change()

      assert has_element?(view, "#gear-cascade-ab")
      assert render(element(view, "#gear-cascade-ab")) =~ "-2"
      refute render(element(view, "#stat-attack_bonus")) == before
    end

    test "the penalty is not silently swallowed by the form", %{view: view} do
      view |> form("#gear-form", %{"ability" => %{"con" => "-4"}}) |> render_change()

      # Число вернулось в поле как введено, а не нулём…
      assert has_element?(view, "#gear-ability-input-con[value='-4']")

      # …и знак не потерялся в свёрнутой сводке: `+-4` было бы ложью про знак.
      summary = render(element(view, "#gear-summary"))
      assert summary =~ "CON -4"
      refute summary =~ "+-4"

      # Отрицательное — это не «за потолком»: срезать нечего.
      refute has_element?(view, "#gear-ability-con[data-capped='1']")
    end

    test "clearing the gear puts every number back", %{view: view} do
      view |> form("#gear-form", %{"ability" => %{"con" => "12"}}) |> render_change()
      assert render(element(view, "#stat-hp")) =~ "717"

      view |> element("#gear-clear") |> render_click()

      assert render(element(view, "#stat-hp")) =~ "471"
      refute has_element?(view, "#gear-cascade")
    end

    # ---------------------------------------------------------------------
    # Задача 3.47 (жалоба Dan: секция «Вещи» набита плотно, «в одних цветах»,
    # «восемнадцать одинаковых нулей»). Тесты закрепляют форму правки, а не
    # только числа: следующая правка не имеет права молча склеить подпись
    # обратно с правилом или стереть разницу между нулём и введённым числом.

    # 🔴 Дефект, а не вкус: «Доспех» просил 37px и получал 17 (замер headless-
    # Chrome), подпись обрезалась до «Д…», и восстановить текст было нельзя
    # ни наведением (`title` не было вовсе), ни на телефоне.
    test "подпись «Надетого» не обрезана и несёт title", %{view: view} do
      html = render(view)

      assert html =~ ~s(title="Доспех")
      assert html =~ ~s(title="Щит")
      assert html =~ ">Доспех<"
      assert html =~ ">Щит<"
    end

    # Правило было вклеено в заголовок («Характеристики — максимум +12 на
    # каждую») и переносилось на две строки в 292px колонке. Теперь это два
    # разных узла: короткий `.gear-lbl` и `.gear-rule` под ним — и следующая
    # правка не должна склеить их обратно в одну строку.
    test "подпись поля и правило про потолок — РАЗНЫЕ строки, не склеены", %{
      view: view,
      ruleset: ruleset
    } do
      assert has_element?(view, ".gear-lbl", "Характеристики")

      assert has_element?(
               view,
               ".gear-rule",
               "максимум +#{ruleset.gear.ability_bonus_cap} на каждую"
             )

      html = render(view)
      refute html =~ "Характеристики — максимум"

      # Задача 3.137 переименовала заголовок в «Спасы» — гвард переименован
      # тем же словом, иначе строка вечно проходила бы вхолостую (слова
      # «Сейвы» в разметке больше нет вовсе, и рефьют был бы истинным при
      # любом исходе, не только при отсутствии склейки).
      refute html =~ "Спасы — общий потолок"
      refute html =~ "Числа оружия — общий потолок"
    end

    # Три списочных подраздела — «Навыки с вещи», «Оружие в руках», «Фиты
    # с вещи» — это ровно то место, где секция делится на смысловые группы
    # (идея из задания: «что надето / числа с вещей / фиты с вещи»). Каждый
    # обязан носить собственный заголовок группы, отдельный от восьми полевых
    # подписей `.gear-lbl` выше.
    test "три раздела списков — «Навыки с вещи», «Оружие в руках», «Фиты с вещи» — со своими заголовками",
         %{view: view} do
      assert has_element?(view, "#gear-skills.gear-feats > .eyebrow", "Навыки с вещи")
      assert has_element?(view, "#gear-weapon.gear-feats > .eyebrow", "Оружие в руках")
      assert has_element?(view, "#gear-feats.gear-feats > .eyebrow", "Фиты с вещи")
    end

    # ⚠️ Скриншот Dan: «восемнадцать одинаковых нулей», не видно, что вообще
    # введено. Ноль и нетронутое поле неотличимы в данных билда, поэтому
    # «заполнено» здесь честно значит «отлично от нуля» — не отдельное
    # состояние «трогали», которого билд не хранит.
    test "нулевое поле не помечено заполненным, введённое — помечено", %{view: view} do
      refute has_element?(view, "#gear-ability-str[data-filled='1']")
      refute has_element?(view, "#gear-ac-armor[data-filled='1']")
      refute has_element?(view, "#gear-saves[data-filled='1']")

      view |> form("#gear-form", %{"ability" => %{"str" => "4"}}) |> render_change()
      assert has_element?(view, "#gear-ability-str[data-filled='1']")

      # Соседи, которых не трогали, остаются непомеченными.
      refute has_element?(view, "#gear-ability-con[data-filled='1']")

      view |> form("#gear-form", %{"saves" => "2"}) |> render_change()
      assert has_element?(view, "#gear-saves[data-filled='1']")
    end

    # Выбранное «Надетое» — тоже выбор, а не число, и та же логика: пока
    # ничего не выбрано, ячейка не помечена заполненной.
    test "выбранное надетое помечено заполненным, «не указано» — нет", %{
      conn: conn,
      ruleset: ruleset
    } do
      %Build{} = base = fighter_41(ruleset)
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(base)}")
      view |> element("#gear-toggle") |> render_click()

      refute has_element?(view, "#gear-worn-armor[data-filled='1']")

      build = %Build{base | gear: Gear.new(worn: %{armor: :full_plate})}
      {:ok, dressed, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      dressed |> element("#gear-toggle") |> render_click()

      assert has_element?(dressed, "#gear-worn-armor[data-filled='1']")
      refute has_element?(dressed, "#gear-worn-shield[data-filled='1']")
    end

    # ---------------------------------------------------------------------
    # Задача 3.63 (Dan, мобильный: «дефолтно стоят нули и когда вводишь
    # что-то, например "6". получается "60" за счёт нуля» — на телефоне
    # курсор встаёт ПЕРЕД литеральным «0», а не выделяет его целиком, и
    # первый набранный символ дописывается к чужой цифре, а не заменяет её).
    #
    # 🔴 Диагноз: поле несло РЕАЛЬНЫЙ символ «0» (`value={row.value}` при
    # нетронутом поле, `filled? == false` — задача 3.47), и любой ввод к нему
    # приписывался. Плейсхолдер несёт то же «сейчас 0», но не лежит в самом
    # поле — печатать в пустое поле, а не поверх чужого символа.
    test "нетронутое числовое поле пустое, с плейсхолдером «0», не с литеральным нулём",
         %{view: view} do
      for id <- ~w(
            gear-ability-input-str
            gear-ac-input-armor
            gear-saves-input
            gear-weapon-attack-input
          ) do
        html = render(element(view, "##{id}"))
        refute html =~ ~s(value="), "#{id} несёт value="
        assert html =~ ~s(placeholder="0"), "#{id} без placeholder"
      end
    end

    # Положительный контроль формы правки: набранное число остаётся
    # литеральным значением поля, как и раньше (плейсхолдер browser сам
    # не покажет поверх настоящего значения).
    test "набранное число остаётся литеральным значением поля", %{view: view} do
      view |> form("#gear-form", %{"ability" => %{"str" => "6"}}) |> render_change()

      assert has_element?(view, "#gear-ability-input-str[value='6']")
      refute has_element?(view, "#gear-ability-input-str[value='60']")
    end
  end

  describe "numbers that hit a ceiling" do
    setup %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(fighter_41(ruleset))}")
      view |> element("#gear-toggle") |> render_click()
      %{view: view}
    end

    test "a save bonus past the cap is marked in the panel, not silently clipped", %{
      view: view,
      ruleset: ruleset
    } do
      cap = ruleset.stat_caps.saving_throw_bonus

      view |> form("#gear-form", %{"saves" => to_string(cap + 10)}) |> render_change()

      for save <- ~w(fort ref will) do
        assert has_element?(view, "#stat-#{save}[data-capped='1']")
        assert render(element(view, "#stat-#{save}")) =~ "кап +#{cap}"
      end

      assert has_element?(view, "#gear-saves-capped")
      assert has_element?(view, "#gear-saves[data-capped='1']")
    end

    test "an ability bonus past the cap says so where it was typed", %{
      view: view,
      ruleset: ruleset
    } do
      view
      |> form("#gear-form", %{
        "ability" => %{"con" => to_string(ruleset.gear.ability_bonus_cap + 8)}
      })
      |> render_change()

      assert has_element?(view, "#gear-ability-con[data-capped='1']")

      assert render(element(view, "#gear-abilities-capped")) =~
               "+#{ruleset.gear.ability_bonus_cap}"

      # The clipped value is what actually reached the hit points.
      assert render(element(view, "#stat-hp")) =~ "717"
    end

    test "nothing is marked while the numbers stay under the ceilings", %{view: view} do
      view |> form("#gear-form", %{"saves" => "5"}) |> render_change()

      refute has_element?(view, "#stat-fort[data-capped='1']")
      refute has_element?(view, "#gear-saves-capped")
    end
  end

  describe "spells" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-sorcerer") |> render_click()
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "the level offers one slot per new spell, by circle", %{view: view} do
      assert has_element?(view, "#section-spells")
      # Sorcerer 1 knows four cantrips and two spells of the first circle.
      assert has_element?(view, "#spell-slot-circle-0-0")
      assert has_element?(view, "#spell-slot-circle-0-3")
      assert has_element?(view, "#spell-slot-circle-1-1")
      refute has_element?(view, "#spell-slot-circle-2-0")
    end

    test "picking a spell fills a slot of its own circle and clearing frees it", %{view: view} do
      view |> element("#spell-light") |> render_click()

      assert has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")
      assert render(element(view, "#spell-slot-circle-0-0")) =~ "Light"
      # A circle 0 spell never lands in a circle 1 slot.
      refute has_element?(view, "#spell-slot-circle-1-0[data-filled='1']")

      view |> element("#spell-clear-circle-0-0") |> render_click()
      refute has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")
    end

    # 🔴 ЗАМЕР Dan 31.08.2026 (задача 3.125), бард 5 с харизмой 11: «видит
    # 2 круг, но не может выбрать на нем заклинания, он как бы заблокирован,
    # это на этапе лвл апа так. При этом в самой игре если нажать B —
    # spellbook, то там второй круг не отображается вообще».
    #
    # Два места, два РАЗНЫХ ответа игры — и тест держит оба сразу, иначе
    # «привели к единообразию» пройдёт незамеченным.
    test "круг не по характеристике: на левелапе виден и заблокирован, в панели спрятан", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :chaotic_good,
          levels: List.duplicate(:bard, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 11}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-5") |> render_click()

      # Пятый уровень барда даёт по одному новому заклинанию 1-го и 2-го круга.
      assert has_element?(view, "#spell-slot-circle-1-0")
      assert has_element?(view, "#spell-slot-circle-2-0")

      # Первый круг обычный, второй — заблокирован и говорит, чего не хватает.
      refute has_element?(view, "#spell-slot-circle-1-0[data-blocked='1']")
      assert has_element?(view, "#spell-slot-circle-2-0[data-blocked='1']")
      assert render(element(view, "#spell-slot-circle-2-0-why")) =~ "CHA 12"

      # В списке заклинание 2-го круга видно и не кликается, 1-го — кликается.
      assert has_element?(view, "#spell-see_invisibility[disabled][data-blocked='1']")
      refute has_element?(view, "#spell-grease[disabled]")

      # А панель итогов (аналог книги заклинаний) второго круга не показывает.
      assert render(element(view, "#spell-day-bard")) =~ "Круг 1:"
      refute render(element(view, "#spell-day-bard")) =~ "Круг 2:"
    end

    # Последнее слово — у ядра, а не у разметки: список нарисован до клика,
    # и событие могло прийти по прежнему состоянию (тот же довод, что у
    # `pick_choice` и выданного выбора).
    test "клик по заблокированному кругу не записывает заклинание", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :chaotic_good,
          levels: List.duplicate(:bard, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 11}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-5") |> render_click()

      render_click(view, "pick_spell", %{"spell" => "see_invisibility"})
      refute has_element?(view, "#spell-slot-circle-2-0[data-filled='1']")

      # Контроль: тем же событием заклинание доступного круга записывается.
      render_click(view, "pick_spell", %{"spell" => "grease"})
      assert has_element?(view, "#spell-slot-circle-1-0[data-filled='1']")
    end

    # Харизма 12 снимает блокировку целиком — то же место, тот же билд.
    test "с харизмой 12 второй круг барда открыт и в списке, и в панели", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :chaotic_good,
          levels: List.duplicate(:bard, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 12}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-5") |> render_click()

      refute has_element?(view, "#spell-slot-circle-2-0[data-blocked='1']")
      refute has_element?(view, "#spell-see_invisibility[disabled]")
      assert render(element(view, "#spell-day-bard")) =~ "Круг 2:"
    end

    test "a chosen spell shows up in the progression column with its circle", %{view: view} do
      view |> element("#spell-magic_missile") |> render_click()

      # The filled group is the one without the "not chosen yet" mark; the
      # circle 0 slots of the same level stay unchosen beside it.
      chosen = render(element(view, "#ladder-spell-1-1"))

      assert chosen =~ "Magic missile"
      assert chosen =~ ">1<"
      refute has_element?(view, "#ladder-spell-1-1[data-todo]")

      # ⚠️ Задача 3.9: `data-todo` у заклинаний убран СОВСЕМ, а не заменён
      # своим цветом — `level_settled?/3` заклинания не спрашивает (комментарий
      # у `settle/2`), и колонка не вправе красить их янтарём как долг, который
      # они не создают. Живой прогон на соркерере, заполненном до капа,
      # с нерасписанными заклинаниями подтвердил: без этой правки жёлтым был
      # весь диапазон уровней 1–20. Текст-подсказка при этом остаётся —
      # положительный контроль ниже проверяет и его, и то, что НАСТОЯЩИЙ долг
      # (общий слот фита этого же уровня, ещё не занятый в этом сценарии)
      # по-прежнему красится как раньше.
      refute has_element?(view, "#ladder-spell-1-0[data-todo]")
      assert render(element(view, "#ladder-spell-1-0")) =~ "выбрать"
      assert has_element?(view, "#level-1 .lv-feat[data-todo='feat']")
    end

    # ⚠️ Шесть слотов первого уровня соркерера давали ШЕСТЬ строк подряд, в
    # каждой одно и то же «выбрать заклинание», — строка лестницы раздувалась
    # вчетверо. Группировка по кругу оставляет две плашки и ни одного потерянного
    # факта: невыбранное считается, выбранное называется поимённо.
    test "the level's slots are grouped by circle, not listed one per row", %{view: view} do
      assert has_element?(view, "#ladder-spell-1-0")
      assert has_element?(view, "#ladder-spell-1-1")
      # Третьей плашки нет — кругов на уровне ровно два.
      refute has_element?(view, "#ladder-spell-1-2")

      # Четыре нулевого круга и два первого — числа, а не четыре и две строки.
      assert render(element(view, "#ladder-spell-1-0")) =~ "×4"
      assert render(element(view, "#ladder-spell-1-1")) =~ "×2"

      # ⚠️ Задача 3.9: шесть заклинаний в счётчик больше не идут — держит
      # уровень только общий слот фита, который здесь и остаётся один пустым.
      # (До фикса тут стояло «7 не выбрано» = 6 заклинаний + 1 фит.)
      assert render(element(view, "#spine-todo")) =~ "1 не выбрано"
    end

    test "a half-filled circle says how many are still owed", %{view: view} do
      view |> element("#spell-light") |> render_click()

      group = render(element(view, "#ladder-spell-1-0"))

      assert group =~ "Light"

      # «ещё» вместо «выбрать»: наполовину собранный круг не должен читаться
      # как нетронутый.
      assert group =~ "ещё ×3"

      # ⚠️ Задача 3.9: счётчик не двигается ни до, ни после этого клика —
      # заклинание никогда в нём не участвовало. Остаётся только общий слот
      # фита, тот же самый «1», что и до выбора заклинания.
      assert render(element(view, "#spine-todo")) =~ "1 не выбрано"
    end

    # ⚠️ Задача 3.9 (повод Dan 03.08.2026): «заклинания долго заполнять,
    # людям может быть лень». Проверено: держать их незачем — `level_settled?/3`
    # заклинания и так не спрашивает, а значит красить их как незавершённость
    # значило бы врать. Билд, который вообще не расписал заклинания на этом
    # уровне, обязан читаться как «всё в порядке», а не как долг.
    test "a level with nothing but unpicked spells never marks itself unfinished", %{
      view: view
    } do
      # Ничего не выбрано нигде на уровне 1, кроме общего слота фита — вот
      # его и берём слотом, чтобы на уровне не осталось НИ ОДНОГО настоящего
      # долга, только шесть пустых заклинаний.
      view |> element("#feat-ok-toughness") |> render_click()

      refute has_element?(view, "[data-spell='1'][data-todo]")
      refute has_element?(view, ".lv-sp-todo[data-todo]")
      assert render(element(view, "#ladder-spell-1-0")) =~ "выбрать"
      assert render(element(view, "#ladder-spell-1-1")) =~ "выбрать"

      # Счётчик согласен: нечего показывать как незавершённое.
      assert has_element?(view, "#spine-todo[data-clear='1']", "всё выбрано")
    end

    test "an already known spell is offered no second time", %{view: view} do
      view |> element("#spell-light") |> render_click()

      assert has_element?(view, "#spell-light[disabled]")
    end

    test "search narrows the list", %{view: view} do
      view |> form("#spell-search-form", %{"q" => "magmis"}) |> render_change()

      assert has_element?(view, "#spell-magic_missile")
      refute has_element?(view, "#spell-light")
    end

    test "slots per day are a derived statistic and live in the totals panel", %{view: view} do
      assert has_element?(view, "#spell-day-sorcerer")
    end

    # AGENT_QUEUE.md 3.50, part B: unlike a feat, a spell with no icon gets no
    # glyph either — the circle badge already answers "what is this", and the
    # box just stays empty so the name still starts at the same left edge.
    test "an icon-bearing spell shows its art; one with none shows an empty box", %{view: view} do
      assert has_element?(view, "#spell-light .game-icon img")

      view |> form("#spell-search-form", %{"q" => "protection"}) |> render_change()

      assert has_element?(view, "#spell-protection_from_alignment")
      refute has_element?(view, "#spell-protection_from_alignment .game-icon img")
      refute has_element?(view, "#spell-protection_from_alignment .game-icon i")
    end
  end

  # AGENT_QUEUE.md 3.54: unlike a feat chip, the spell chip's icon ADDS to the
  # circle badge rather than replacing it — the badge carries the one piece of
  # information (which circle) nowhere else in the chip says at all.
  describe "иконка в чипе слота заклинания — задача 3.54" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-sorcerer") |> render_click()
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    test "a filled slot shows the spell's art beside the circle badge, not instead of it", %{
      view: view
    } do
      view |> element("#spell-light") |> render_click()

      assert has_element?(view, "#spell-slot-circle-0-0[data-filled='1'] .game-icon img")
      assert has_element?(view, "#spell-slot-circle-0-0[data-filled='1'] .circle-badge")
    end

    test "a filled slot whose spell carries no art shows an empty box, never a made-up glyph", %{
      view: view
    } do
      view
      |> form("#spell-search-form", %{"q" => "protection"})
      |> render_change()

      view |> element("#spell-protection_from_alignment") |> render_click()

      assert has_element?(view, "#spell-slot-circle-1-0[data-filled='1'] .game-icon")
      refute has_element?(view, "#spell-slot-circle-1-0 .game-icon img")
      refute has_element?(view, "#spell-slot-circle-1-0 .game-icon i")
    end

    test "an unfilled slot carries no icon element at all — nothing chosen, nothing to show art for",
         %{view: view} do
      refute has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")
      refute has_element?(view, "#spell-slot-circle-0-0 .game-icon")
    end
  end

  describe "the wall at class level 20" do
    setup %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:sorcerer, 21),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 14}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-21") |> render_click()
      %{view: view}
    end

    test "the section says out loud that the table ends, instead of showing nothing", %{
      view: view,
      ruleset: ruleset
    } do
      max = ruleset.classes.sorcerer.spell_table_max_class_level

      note = render(element(view, "#spell-note"))

      assert note =~ "#{max}-м уровне класса"
      assert note =~ "HP, спасы и фиты"
      # No slots at all past the table, so there is nothing to pick.
      refute has_element?(view, "#spell-search-form")
    end

    test "the totals panel repeats the wall next to the slots per day", %{view: view} do
      assert has_element?(view, "#spell-day-wall-sorcerer")
    end
  end

  describe "gaps" do
    # 🔴 Задача 3.88 (24.08.2026, решение Dan): раньше эта секция ВСЕГДА
    # показывала разбор `ruleset.gaps` по трём разрядам. Список сегодня —
    # 0 настоящих дыр / 8 решённых расхождений / 8 принятых допущений
    # (`gaps_test.exs`), то есть целиком РЕШЕНИЯ, и «данную секцию с сайта
    # уже убрал бы… для пользователей я предлагаю дыры больше не
    # показывать». Тест держит положительную и отрицательную половину
    # рядом: гэпы ЭТОГО билда (`#gaps-body`) остаются видимыми всегда,
    # блок гэпов ДАННЫХ (`#gaps-data`) — только пока `data_real_count > 0`.
    test "with today's data (no real gap) the panel body has no data breakdown", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      build = Build.new(ruleset_version: ruleset.version)
      summary = Gaps.summary(ruleset, build, Rules.compute(build, ruleset))
      assert summary.data_real_count == 0

      assert has_element?(view, "#gaps-toggle")
      view |> element("#gaps-toggle") |> render_click()

      assert has_element?(view, "#gaps-body")
      refute has_element?(view, "#gaps-data")

      # Методология осталась доступна — за ссылкой, а не молчанием.
      assert has_element?(view, "#gaps-sources-link")
    end

    # ⚠️ Задача 3.49 (18.08.2026): раньше `ruleset.gaps` рисовался одним
    # плоским списком, и «источники спорят про Discipline у Purple dragon
    # knight» стояло в одном ряду с настоящей дырой — «расовый бонус ниже
    # 40-го не считаем». Три блока разводят их по смыслу
    # (`BuildCalculatorWeb.Builder.Gaps.tier/1`): настоящие дыры первыми
    # и без приглушения, решённое и принятое — тише (класс `gaps-quiet`),
    # но не спрятано — оба видны без дополнительного клика, как только
    # раскрыта сама панель.
    #
    # 🔴 Задача 3.88: с тех пор как разряд настоящих дыр опустел (3.86),
    # весь блок целиком гейтится — значит проверить его форму можно только
    # на СИНТЕТИЧЕСКОМ ruleset'е с наведённой дырой (постановка задачи
    # предупреждает: живые данные молча перестали бы что-либо ловить).
    # `render_assigns/2` рендерит шаблон напрямую, поэтому проверка идёт
    # через `LazyHTML` (`AGENTS.md`: правильный инструмент для скоуп-запроса
    # по сырой разметке, а не обход `element/2` — тут просто нет `view`,
    # который можно было бы запросить им).
    test "the data gaps split into three tiers, real ones first and unmuted, once a real gap exists",
         %{conn: conn, ruleset: ruleset} do
      {:ok, view, _html} = live(conn, ~p"/")

      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      synthetic_ruleset = %{ruleset | gaps: [induced | ruleset.gaps]}
      build = Build.new(ruleset_version: ruleset.version)

      synthetic_gaps =
        Gaps.summary(synthetic_ruleset, build, Rules.compute(build, synthetic_ruleset))

      html = render_assigns(view, %{gaps: synthetic_gaps, gaps_open?: true})
      doc = LazyHTML.from_fragment(html)

      real = doc |> LazyHTML.query("#gaps-data-real") |> LazyHTML.to_html()
      resolved = doc |> LazyHTML.query("#gaps-data-resolved") |> LazyHTML.to_html()
      assumed = doc |> LazyHTML.query("#gaps-data-assumed") |> LazyHTML.to_html()

      refute real == ""
      refute resolved == ""
      refute assumed == ""

      # Настоящие дыры — «Не смоделировано» (наведённая запись), а не
      # решённые споры и не допущения.
      refute real =~ "Источники спорят"
      refute real =~ "Допущения"
      assert real =~ "Не смоделировано"
      assert real =~ "Toughness"

      assert resolved =~ "Источники спорят"
      assert assumed =~ "Допущения"

      # Приглушение — модификатор класса, а не отдельная вёрстка: у блока
      # с настоящими дырами его нет, у решённого и принятого — есть.
      assert Enum.empty?(LazyHTML.query(doc, "#gaps-data-real.gaps-quiet"))
      refute Enum.empty?(LazyHTML.query(doc, "#gaps-data-resolved.gaps-quiet"))
      refute Enum.empty?(LazyHTML.query(doc, "#gaps-data-assumed.gaps-quiet"))

      # base_ac цитирует страницу, а не заявляет, что источника нет —
      # положительный и отрицательный контроль в одном тесте: строка на
      # месте (в тихом блоке допущений), а старая ложь — нет.
      assert assumed =~ "fandom:Armor class"
      refute assumed =~ "страницы про это нет"
    end

    # ⚠️ Долг из AGENT_QUEUE §7: панель показывала выборку и не говорила об этом.
    # Своя половина («…и ещё N») была честной и раньше — врала половина про
    # ДАННЫЕ: под заголовком со полным числом стоял список из нескольких строк
    # и ни слова о том, что это начало. Тест держит оба числа рядом, потому что
    # поодиночке каждое выглядит правдой.
    #
    # 🔴 Задача 3.88: тот же гейт, что у теста выше — сегодня блока с выборкой
    # нет вовсе, значит проверяется он на том же наведённом ruleset'е.
    test "панель называет размер выборки, а не только полное число, once a real gap exists", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      induced = {:not_modelled, {:feat_change, :toughness, "3.88 synthetic gap"}}
      synthetic_ruleset = %{ruleset | gaps: [induced | ruleset.gaps]}
      build = Build.new(ruleset_version: ruleset.version)

      synthetic_gaps =
        Gaps.summary(synthetic_ruleset, build, Rules.compute(build, synthetic_ruleset))

      html = render_assigns(view, %{gaps: synthetic_gaps, gaps_open?: true})
      doc = LazyHTML.from_fragment(html)

      sample = doc |> LazyHTML.query("#gaps-data-sample") |> LazyHTML.to_html()
      shown = doc |> LazyHTML.query("#gaps-data li") |> Enum.count()

      # Полное число — длина ruleset'а, а не наше представление о ней.
      assert sample =~ "из #{length(synthetic_ruleset.gaps)}"
      assert sample =~ "Показаны #{shown}"

      # Положительный контроль: выборка действительно выборка, иначе утверждение
      # «показаны N из M» было бы правдой и при N == M, и тест ничего бы не ловил.
      assert shown < length(synthetic_ruleset.gaps)
      assert shown > 0
    end

    # ⚠️ Здесь стояло «a build whose hit die is unknown reports it instead of
    # inventing HP» — тот же билд, та же причина, что и у соседа выше: задача
    # 3.37 прочитала растущий хит-дайс Ученика красного дракона, и ни «?»,
    # ни оговорки про хит-дайс у него больше нет. Кейс требует ОБРАТНОГО:
    # число на месте, а слова «хит-дайс» в панели пробелов нет. Оговорка,
    # которая перестала быть правдой, обязана исчезнуть с экрана — иначе
    # она учит игрока пролистывать этот список (CLAUDE.md §9).
    test "a build with a growing hit die shows the number and drops the caveat", %{conn: conn} do
      build =
        Build.new(
          ruleset_version: Data.default_version(),
          levels: [:sorcerer, :sorcerer, :sorcerer, :sorcerer, :sorcerer, :red_dragon_disciple]
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Колдун 5 × d4 = 20, РДД 1 = d6, CON 10 (мод 0), «Дух Сиалы» +20.
      assert render(element(view, "#stat-hp")) =~ "46"
      refute render(element(view, "#stat-hp")) =~ "?"

      view |> element("#gaps-toggle") |> render_click()
      refute render(element(view, "#gaps-body")) =~ "хит-дайс"
    end

    # Хвост задачи 3.28 (пункт 2): атрибуция и так есть в футере на каждой
    # странице, но клик рядом со списком неточностей удобнее прокрутки к нему.
    test "панель ссылается на страницу «Источники»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#gaps-toggle") |> render_click()

      assert has_element?(view, "#gaps-body #gaps-sources-link")

      {:ok, sources, _html} =
        view |> element("#gaps-sources-link") |> render_click() |> follow_redirect(conn)

      assert has_element?(sources, "#sources-page")
    end
  end

  describe "the build in the URL" do
    test "every change patches the address bar", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()
      path = assert_patch(view)

      assert path =~ "?b=#{Encoding.current_version()}."
    end

    test "a shared link opens the same build", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()
      assert_patch(view)
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      path = assert_patch(view)

      {:ok, reopened, _html} = live(conn, path)

      assert has_element?(reopened, "#split-fighter")
      assert render(element(reopened, "#character-level")) =~ "1"
      assert render(element(reopened, "#class-split")) =~ "Гном"

      # ⚠️ Задача 3.61: здесь стояло `refute has_element?(reopened,
      # "#race-card-dwarf")` — это проверяло не «ссылка открывает тот же
      # билд», а побочный эффект старого бага: ссылка садила на «следующий
      # после последнего взятого» (тут — уровень 2), и секция расы (видна
      # только на уровне 1) закономерно не рисовалась. Теперь адрес несёт
      # саму позицию (`l=1` — билд собирался на уровне 1), и ссылка
      # возвращает ИМЕННО туда, с расой уже отмеченной выбранной — то есть
      # прямо то, что доказывает заголовок теста.
      assert has_element?(reopened, "#stage-title", "Уровень 1")
      assert has_element?(reopened, "#race-card-dwarf[data-chosen='1']")
    end

    test "a mangled link opens an empty builder with a message, not a crash", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=1.not-a-real-code")

      assert render(element(view, "#character-level")) =~ "0"
      assert render(view) =~ "битая"
    end

    test "a link from an unknown schema version is refused politely", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?b=99.abcdef")

      assert render(element(view, "#character-level")) =~ "0"
      assert render(view) =~ "версией кодировки"
    end
  end

  # Задача 3.66 (баг, нашёл Dan 20.08.2026). Жалоба: «когда обновляю страницу
  # мне предлагают эти фиты взять... потом в какой-то момент фильтр
  # срабатывает и они пропадают». Причина не в фильтре и не в ядре: `mount/3`
  # заканчивался `refresh()` для ПУСТОГО билда 1-го уровня, а
  # `handle_params/3` → `load_code/3` тут же делал ВТОРОЙ `refresh()` для
  # настоящего билда — и оба раза, до первого рендера. `stream(..., reset:
  # true)` не чистит накопленное немедленно (чистит хук `:after_render`,
  # уже ПОСЛЕ рендера), поэтому два вызова подряд без рендера между ними не
  # заменяли списки фитов, а СКЛАДЫВАЛИ их: в HTML утекали строки пустого
  # билда (`toughness`, региональные фиты и т.п.) вперемешку со строками
  # настоящего.
  #
  # ⚠️ Обязателен именно `get/2` + `html_response/2` на мёртвом (статическом)
  # рендере, а не только `live/2`: `mount/3` вызывается заново и независимо
  # для КАЖДОГО процесса — и для мёртвого рендера, и для коннекта — и в обоих
  # гонка одна и та же (первый `refresh()` в `mount/3` до того, как
  # `handle_params/3` подменит билд своим). На живом сервере игрок видит эту
  # гонку только на мёртвом рендере, потому что после коннекта браузер обычно
  # успевает получить diff от подключённого процесса раньше, чем что-то
  # щёлкнуть, — а вот в этом харнессе `live/2` ничего не «успевает», у него
  # своя гонка та же самая, и ниже это отдельно проверено (`live/2` тоже
  # красный без фикса). Держим оба теста: мёртвый — потому что это то самое
  # место, которое `Phoenix.LiveViewTest.live/2` в общем случае не обязан
  # ловить (он уже подключён к моменту, когда возвращает управление), живой —
  # потому что здесь он тоже ловит, и это не будет для читателя сюрпризом.
  describe "холодный старт по ссылке не смешивает потоки фитов (задача 3.66)" do
    test "статический (мёртвый) рендер не удваивает списки", %{conn: conn, ruleset: ruleset} do
      build = fighter_36_of_41(ruleset)
      code = Encoding.encode(build)

      # «Правда» — тот же вызов, что сделает единственный `refresh()` после
      # фикса: настройки по умолчанию (без поиска, без фильтра, без слота).
      truth = Feats.lists(ruleset, build, 36, query: "", type: "all", slot: nil)
      truth_available = MapSet.new(truth.available, &"feat-ok-#{&1.feat.id}")
      truth_blocked = MapSet.new(truth.blocked, &"feat-no-#{&1.feat.id}")

      conn = get(conn, ~p"/?b=#{code}")
      doc = conn |> html_response(200) |> LazyHTML.from_fragment()

      rendered_available =
        doc |> LazyHTML.query("[id^='feat-ok-']") |> LazyHTML.attribute("id") |> MapSet.new()

      rendered_blocked =
        doc |> LazyHTML.query("[id^='feat-no-']") |> LazyHTML.attribute("id") |> MapSet.new()

      # `assert_equal` через `MapSet` вместо счётчика строк: расхождение в
      # СОСТАВЕ (не только в числе) — это ровно то, что было багом здесь
      # (лишние `feat-ok-toughness` и подобные, а не просто "больше строк").
      assert rendered_available == truth_available
      assert rendered_blocked == truth_blocked

      count_text = doc |> LazyHTML.query("#feats-available-count") |> LazyHTML.text()

      assert count_text == "Доступные · #{length(truth.available)}"
    end

    test "рендер после коннекта на ту же ссылку не удваивает списки", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter_36_of_41(ruleset)
      code = Encoding.encode(build)

      truth = Feats.lists(ruleset, build, 36, query: "", type: "all", slot: nil)
      truth_available = MapSet.new(truth.available, &"feat-ok-#{&1.feat.id}")
      truth_blocked = MapSet.new(truth.blocked, &"feat-no-#{&1.feat.id}")

      {:ok, view, html} = live(conn, ~p"/?b=#{code}")

      for source <- [html, render(view)] do
        doc = LazyHTML.from_fragment(source)

        rendered_available =
          doc |> LazyHTML.query("[id^='feat-ok-']") |> LazyHTML.attribute("id") |> MapSet.new()

        rendered_blocked =
          doc |> LazyHTML.query("[id^='feat-no-']") |> LazyHTML.attribute("id") |> MapSet.new()

        assert rendered_available == truth_available
        assert rendered_blocked == truth_blocked
      end
    end

    test "пустой конструктор без ?b= по-прежнему предлагает фиты 1-го уровня", %{conn: conn} do
      conn = get(conn, ~p"/")
      doc = conn |> html_response(200) |> LazyHTML.from_fragment()

      refute doc |> LazyHTML.query("[id^='feat-ok-']") |> Enum.empty?()

      count_text = doc |> LazyHTML.query("#feats-available-count") |> LazyHTML.text()

      refute count_text == "Доступные · 0"
    end

    test "битая ссылка на мёртвом рендере — тоже не удваивает список, а не падает",
         %{conn: conn} do
      conn = get(conn, ~p"/?b=1.not-a-real-code")
      html = html_response(conn, 200)
      doc = LazyHTML.from_fragment(html)

      assert html =~ "битая"
      refute doc |> LazyHTML.query("[id^='feat-ok-']") |> Enum.empty?()

      count_text = doc |> LazyHTML.query("#feats-available-count") |> LazyHTML.text()

      refute count_text == "Доступные · 0"
    end
  end

  # Задача 3.61. Dan: «когда хром свёрнутый сокет прибивает, после
  # восстановления кидает сразу на последний уровень. Если ты правил
  # что-то в середине, переставит на последний». Причина была в
  # `load_code/2`: свежий сокет не помнил `active`, и загрузка билда из
  # адреса всегда садилась на `taken + 1`. Путь 1 из постановки: уровень
  # едет в адрес вторым параметром `l`, рядом с `b`.
  describe "уровень редактора переживает переподключение (задача 3.61)" do
    # ⚠️ В этом харнессе «сокет прибили и восстановили» и «страницу
    # перезагрузили целиком» неотличимы — оба смоделированы новым `live/2`
    # по тому же адресу (AGENT_QUEUE §3.61: «переподключение в тесте
    # моделируется новым live/2»), и оба проходят один и тот же путь —
    # свежий `mount/3`, затем `handle_params/3`. Отдельного теста на
    # «полную перезагрузку» нет намеренно: он был бы побайтовым дублем.
    test "переход по лестнице без правки билда переживает переподключение", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter_36_of_41(ruleset)
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # До перехода — «следующий после последнего взятого» (35 + 1), старое
      # поведение, которое и уводило игрока на последний уровень.
      assert has_element?(view, "#stage-title", "Уровень 36")

      view |> element("#level-20") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 20")

      path = assert_patch(view)
      assert path =~ "l=20"

      {:ok, reconnected, _html} = live(conn, path)

      assert has_element?(reconnected, "#stage-title", "Уровень 20")
      refute has_element?(reconnected, "#stage-title", "Уровень 36")
    end

    # Ровно жалоба Dan: «если ты правил что-то в середине». Правка билда
    # (`put_build/2` — воронка, через которую идёт КАЖДОЕ изменение) обязана
    # нести ту же позицию, что и голый переход по лестнице выше.
    test "правка на уровне в середине билда тоже переживает переподключение", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter_36_of_41(ruleset)
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#level-20") |> render_click()
      assert_patch(view)

      # Уровень 20 кратен 4 — секция прибавки к характеристике на нём есть
      # независимо от того, что это уже взятый, а не новый уровень.
      view |> element("#increase-card-str") |> render_click()
      path = assert_patch(view)
      assert path =~ "l=20"

      {:ok, reconnected, _html} = live(conn, path)

      assert has_element?(reconnected, "#stage-title", "Уровень 20")
      assert has_element?(reconnected, "#increase-card-str[data-chosen='1']")
    end

    # ⚠️ Зажим — ОДНА функция (`clamp_level/3`) на клик по лестнице и на
    # адрес, поэтому мусор в `l` обязан вести себя ровно так, как повёл бы
    # себя такой же мусор, отправленный в `select_level` руками.
    test "уровень из адреса зажат тем же min(taken + 1), что и select_level", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter_36_of_41(ruleset)
      code = Encoding.encode(build)

      # `l=999` просит уровень за концом билда — зажимается до 36 (35 + 1),
      # ровно как клик по несуществующей строке лестницы.
      {:ok, over, _html} = live(conn, ~p"/?b=#{code}&l=999")
      assert has_element?(over, "#stage-title", "Уровень 36")

      # `l=-5` и `l=0` — ниже пола. `#level-0` в лестнице сам ведёт на 1
      # (задача 3.17), адрес обязан вести туда же, а не показывать пустой
      # экран или падать.
      {:ok, negative, _html} = live(conn, ~p"/?b=#{code}&l=-5")
      assert has_element?(negative, "#stage-title", "Уровень 1")

      {:ok, zero, _html} = live(conn, ~p"/?b=#{code}&l=0")
      assert has_element?(zero, "#stage-title", "Уровень 1")

      # `l=abc` не парсится вовсе — «нет запроса», не отдельная ветка: то же
      # «Уровень 36», что и без параметра `l` совсем.
      {:ok, garbage, _html} = live(conn, ~p"/?b=#{code}&l=abc")
      assert has_element?(garbage, "#stage-title", "Уровень 36")

      # А обычный валидный запрос по-прежнему просто работает.
      {:ok, ok, _html} = live(conn, ~p"/?b=#{code}&l=20")
      assert has_element?(ok, "#stage-title", "Уровень 20")
    end

    test "чужая ссылка (share-link) не несёт позицию редактирования", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter_36_of_41(ruleset)
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#level-20") |> render_click()
      assert_patch(view)

      # `view_url/1` строит адрес из одного `code`, не заглядывая в
      # `active` — значит share-link не понесёт `l=` независимо от того,
      # что происходит в адресе самого редактора. Иначе позиция
      # разъехалась бы по чужим ссылкам в Discord.
      link_html = render(element(view, "#share-link"))
      assert link_html =~ "/b/"
      refute link_html =~ "l="
    end

    # ⚠️ «Уклон: нет» из постановки — секции и второй шаг выбора фита
    # восстанавливать опасно (недоделанный выбор с параметром — половина
    # решения). Тест закрепляет это как проверенное решение, а не как то,
    # что попросту не заметили.
    test "второй шаг выбора фита не восстанавливается после переподключения", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()
      path = assert_patch(view)

      # Второй шаг выбора фита билд и адрес не трогает вовсе
      # (`open_choice/4`, а не `put_build/2`) — восстанавливать его после
      # переподключения и так неоткуда.
      view |> element("#feat-ok-spell_focus") |> render_click()
      assert has_element?(view, "#feat-choice")

      {:ok, reconnected, _html} = live(conn, path)
      refute has_element?(reconnected, "#feat-choice")
    end
  end

  describe "клик по «N не выбрано» ведёт к пропуску (задача 3.60)" do
    # ⚠️ Раньше здесь был `<span>` — не кликался ни мышью, ни клавиатурой.
    # Когда пропусков нет, кликать не по чему: `disabled`, а не мёртвый
    # `phx-click`, — элемент не обязан обещать действие, которого не будет.
    test "без пропусков кнопка отключена и не несёт phx-click", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "button#spine-todo[data-clear='1']", "всё выбрано")
      assert has_element?(view, "#spine-todo[disabled]")
      refute has_element?(view, "#spine-todo[phx-click]")
    end

    # Ровно пример Dan: «пропустил на 20 лвл фит. Сам уже на 35 уровне…
    # нажимаешь на "1 не выбрано" и тебя переводит на 20 уровень в раздел
    # фитов». Все прочие слоты и прибавки заполнены — иначе первым пропуском
    # оказался бы уровень 1, и тест проверял бы совсем не тот путь.
    test "клик переводит с 35-го на 20-й уровень и подводит экран к секции фитов", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = fighter_with_gaps(ruleset, 35, skip_feats: [20])
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#level-35") |> render_click()

      # ⚠️ Осушить патч ОТ ЭТОГО клика прямо здесь: `assert_patch/1` читает
      # ОДНО сообщение из почтового ящика в порядке прихода (FIFO, тот же
      # урок, что и в задаче 3.61), и непотреблённый патч перехода на 35-й
      # подменил бы собой патч следующего клика — по «Уровень 20» вместо
      # ожидаемого.
      assert_patch(view)
      assert has_element?(view, "#stage-title", "Уровень 35")
      assert render(element(view, "#spine-todo")) =~ "1 не выбрано"

      view |> element("#spine-todo") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 20")
      path = assert_patch(view)
      assert path =~ "l=20"

      # Прыжок — это НЕ автодвижение, снятое задачей 3.30 (`.FocusPending`,
      # `settle/2`): здесь есть явный клик, а прокрутку несёт `push_event`,
      # который слушает `.ScrollBus` (задача 3.60, `builder_live.html.heex`).
      assert_push_event(view, "scroll_to_section", %{id: "section-feats"})

      # Мобильная лента отвечает на тот же вопрос теми же id — «вкладки
      # внизу» из постановки читают `BuilderLive.assign_stage_nav/1`, ту же
      # функцию, что и прыжок: сменить уровень и не тронуть вкладку было бы
      # ровно той половинчатой правкой, которую задача просила избежать.
      assert has_element?(view, "#stage-nav-feats[data-state='hold']")

      # Тот самый пропущенный слот пуст — не какой-то другой.
      refute has_element?(view, "#slot-chip-class_bonus-fighter[data-filled]")
    end

    # Уровень 20 пропущен и в прибавке к характеристике, и в слоте фита разом
    # — оба «держат» уровень (`holds_level?/2`). Порядок секций сверху вниз
    # (`nav_sections/1`): стат стоит раньше фитов, и прыжок обязан вести туда
    # же, куда смотрит игрок первым, а не туда, что просто нашлось раньше
    # при переборе.
    test "на одном уровне выше приоритет у стата, чем у фита", %{conn: conn, ruleset: ruleset} do
      build = fighter_with_gaps(ruleset, 35, skip_feats: [20], skip_increases: [20])
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#spine-todo") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 20")
      assert_push_event(view, "scroll_to_section", %{id: "section-increase"})
    end

    # Обязательный выбор класса (домены клирика) держит уровень так же, как
    # пустой слот фита (`holds_level?(assigns, "domains")`), и стоит в ленте
    # ЕЩЁ выше фитов. Уровень 1 клирика без выбранных доменов и без взятого
    # общего фита — прыжок обязан вести в «Домены», а не в «Фиты».
    test "домены клирика перевешивают пустой слот фита на том же уровне", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:cleric],
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 14, cha: 10}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#spine-todo") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 1")
      assert_push_event(view, "scroll_to_section", %{id: "section-domains"})
    end

    # Вопрос 3 постановки: «повторный клик» обязан вести к СЛЕДУЮЩЕМУ
    # пропуску после того, как первый закрыт — обычный цикл «дальше по
    # списку», а не залипание на одном и том же месте.
    test "починил пропуск — следующий клик ведёт к следующему", %{conn: conn, ruleset: ruleset} do
      build = fighter_with_gaps(ruleset, 35, skip_feats: [20], skip_increases: [4])
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert render(element(view, "#spine-todo")) =~ "2 не выбрано"

      view |> element("#spine-todo") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 4")
      assert_push_event(view, "scroll_to_section", %{id: "section-increase"})

      # Закрываем первый пропуск прямо на месте, куда нас перевело.
      view |> element("#increase-card-str") |> render_click()
      assert render(element(view, "#spine-todo")) =~ "1 не выбрано"

      view |> element("#spine-todo") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 20")
      assert_push_event(view, "scroll_to_section", %{id: "section-feats"})

      # Второй тоже закрылся — кнопка снова отключается. ⚠️ `cleave`, не
      # `power_attack`: этим последним фикстура заполнила ВСЕ остальные
      # слоты напрямую (`Build.new`, легальность там не проверяется), так
      # что список доступных фитов сам отказал бы «уже есть у персонажа».
      # `cleave` требует `power_attack` — а он у билда есть — и нигде
      # больше в фикстуре не занят.
      view |> element("#feat-ok-cleave") |> render_click()
      assert has_element?(view, "#spine-todo[data-clear='1']", "всё выбрано")
      assert has_element?(view, "#spine-todo[disabled]")
    end
  end

  describe "guided mode (задача 3.157)" do
    # Задача 3.163: значок «что делает режим гида» стоит РЯДОМ с галочкой,
    # а не вместо неё, и объясняет её вслух. Разметка ничем больше не
    # защищена — клиентское поведение `.FeatInfo` живёт в `assets/test/`
    # (`Phoenix.LiveViewTest` колокированные хуки не исполняет вовсе,
    # CLAUDE.md §7), поэтому здесь смок ровно на то, что доступно серверу:
    # значок есть, он тот же переиспользованный механизм, и текст описания
    # доехал до атрибута, а не потерялся по дороге.
    test "рядом с галочкой стоит ⓘ с описанием того, что делает гид", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#guided-toggle-input")
      assert has_element?(view, "#guided-mode-info.feat-info")

      description =
        view
        |> element("#guided-mode-info")
        |> render()

      # Слово Dan 01.09.2026: упор на САМО ДЕЙСТВИЕ («прокрутит экран»),
      # а не на намерение («поведёт к следующему решению») — проверяем
      # именно глагол действия и слово «обязательн», в котором и живёт
      # критерий «нельзя отложить».
      assert description =~ "рокручивает экран"
      assert description =~ "обязательной секции"
    end

    # Задача 3.163: `title` на самом `<label>` снят — он был ховер-онли
    # (на тач не достаётся вовсе) И его формулировка разошлась со словом
    # Dan. Второй, конфликтующий по тексту канал подсказки — хуже, чем
    # один; если `title` вернут, этот тест скажет об этом вслух.
    test "у самого лейбла ховер-онли title больше нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute view |> element("#guided-toggle") |> render() =~ "title="
    end

    # Требование 2 постановки: без единого клика по галочке ничего не едет —
    # `guided_mode` в `mount/3` стоит `false`, и `guide_scroll/2` первым же
    # условием `with` его читает.
    test "выключено по умолчанию — выбор расы не двигает экран", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()

      refute_push_event(view, "scroll_to_section", %{})
    end

    # Ровно пример постановки: раса → мировоззрение → класс, один шаг за
    # раз. `render_hook` — тот же путь, каким `.GuidedMode` шлёт
    # `"set_guided_mode"` из `mounted()`/`change`, не форма и не `phx-click`.
    test "включённое ведёт от расы к мировоззрению и от мировоззрения к классу", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "set_guided_mode", %{"value" => true})

      view |> element("#race-card-human") |> render_click()
      assert_push_event(view, "scroll_to_section", %{id: "section-alignment", block: "nearest"})

      view |> element("#alignment-lawful_good") |> render_click()
      assert_push_event(view, "scroll_to_section", %{id: "section-class", block: "nearest"})
    end

    # `block: "nearest"` — НЕ дефолт `.ScrollBus` (`jump_to_gap`/
    # `jump_to_gear_issue` просят `"start"`), и урок, почему это разные
    # значения, стоит рядом с `guide_scroll/2`. Тест держит число буквально,
    # а не только факт вызова — иначе правка, забывшая передать `block`,
    # осталась бы зелёной.
    test "цель приходит с block: nearest, а не start", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "set_guided_mode", %{"value" => true})

      view |> element("#race-card-human") |> render_click()

      refute_push_event(view, "scroll_to_section", %{id: "section-alignment", block: "start"})
      assert_push_event(view, "scroll_to_section", %{id: "section-alignment", block: "nearest"})
    end

    # Тот же принцип, каким снятый `.FocusPending` сравнивал `token()`:
    # скроллим, только когда ПЕРВАЯ незакрытая секция реально сменилась —
    # не при каждом проходе воронки. Раса и мировоззрение уже закрыты (цель —
    # «section-class»), а клик по поинт-баю класс не трогает: цель до и
    # после ОДНА И ТА ЖЕ, второго `scroll_to_section` тут быть не должно.
    test "цель не сдвинулась — повторного скролла нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      render_hook(view, "set_guided_mode", %{"value" => true})

      view |> element("#race-card-human") |> render_click()
      assert_push_event(view, "scroll_to_section", %{id: "section-alignment"})

      view |> element("#alignment-lawful_good") |> render_click()
      assert_push_event(view, "scroll_to_section", %{id: "section-class"})

      view |> element("#point-buy-str-up") |> render_click()
      refute_push_event(view, "scroll_to_section", %{})
    end

    # 🔴 Уточнение владельца шарда через Dan в ходе работы над задачей:
    # навыки — «не потрачено», а не «не решено», копить и вложить позже —
    # законная стратегия. Билд ниже закрывает ВСЁ, кроме навыков (раса,
    # мировоззрение, класс, поинт-бай — 30 из 30, единственный слот фита
    # заполнен), так что не-эльф-фактор не мешает: если бы навыки были
    # законной целью, свободные очки были бы ЕДИНСТВЕННЫМ, к чему может
    # вести guide_scroll. Тратим один ранг обычным кликом (а не максом —
    # чтобы билд остался «есть что копить») и проверяем, что экран никуда
    # не поехал.
    test "навыки не цель — свободные очки не тащат экран к себе", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :chaotic_good,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 18},
          feats: %{1 => %{:general => :toughness, {:class_bonus, :fighter} => :great_fortitude}},
          # Строка обязана существовать в списке ДО клика — панель показывает
          # только навыки, в которые билд уже вкладывается (CLAUDE.md §6), а
          # «+1» кликают на СУЩЕСТВУЮЩЕЙ строке.
          skills: %{1 => %{appraise: 1}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # ⚠️ `?b=` без `l=` открывает СЛЕДУЮЩИЙ непройденный уровень
      # (`load_code/2`: `requested_level(params) || taken + 1`), а у билда
      # из одного уровня это 2-й — там ни класса, ни навыков ещё нет.
      # Уровень 1, где и стоит проверяемое, нужен явным кликом.
      view |> element("#level-1") |> render_click()
      render_hook(view, "set_guided_mode", %{"value" => true})

      # Положительный контроль на саму фикстуру: если бы навыки НЕ были
      # исключены, вот куда поехал бы экран, — а «незакрыт» здесь и
      # означает «есть что потратить», не «билд неполон».
      assert has_element?(view, "#stage-nav-skills[data-state='todo']")

      view |> element("#skill-plus-appraise") |> render_click()

      refute_push_event(view, "scroll_to_section", %{})
    end

    # 🔴 Тот же довод для заклинаний, дословно Dan: «тот кто будет билдить
    # барда или колдуна может залениться заполнять все заклинания, это
    # довольно утомительно… guided mode соответственно никогда не должен
    # скроллить к заклинаниям». Колдун 1-го уровня без единого известного
    # заклинания — секция «Заклинания» незакрыта (шесть пустых слотов), а
    # экран никуда не едет ни на монтировании guided mode, ни на выборе
    # ОДНОГО заклинания (которое явно оставляет секцию незакрытой — под
    # тестом именно "не тянет", а не "уже закрыто по случайности").
    test "заклинания не цель — выбор известного заклинания не двигает экран", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :chaotic_good,
          levels: [:sorcerer],
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 18},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Та же ловушка, что у соседнего теста навыков — билд из одного
      # уровня без `l=` открывается на 2-м, ещё пустом.
      view |> element("#level-1") |> render_click()
      render_hook(view, "set_guided_mode", %{"value" => true})

      # Положительный контроль: секция и правда не закрыта.
      assert has_element?(view, "#stage-nav-spells[data-state='todo']")
      refute has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")

      view |> element("#spell-light") |> render_click()

      assert has_element?(view, "#spell-slot-circle-0-0[data-filled='1']")
      refute_push_event(view, "scroll_to_section", %{})
    end

    # Требование 3 постановки: галочка — настройка ЧИТАТЕЛЯ, не билда, и
    # `Encoding.encode/1` от неё не зависит побайтово. Один и тот же клик
    # из одинаковой стартовой точки — с выключенной галочкой и с включённой
    # — обязан дать один и тот же адрес.
    test "код билда в URL не зависит от галочки", %{conn: conn} do
      {:ok, off, _html} = live(conn, ~p"/")
      off |> element("#race-card-human") |> render_click()
      path_off = assert_patch(off)

      {:ok, on, _html} = live(conn, ~p"/")
      render_hook(on, "set_guided_mode", %{"value" => true})
      on |> element("#race-card-human") |> render_click()
      path_on = assert_patch(on)

      # Осушаем скролл этого клика, иначе он остаётся висеть в почтовом
      # ящике `on` и не мешает ЭТОМУ тесту, но незачем оставлять за собой
      # непотреблённые сообщения.
      assert_push_event(on, "scroll_to_section", %{id: "section-alignment"})

      assert URI.parse(path_off).query == URI.parse(path_on).query
    end

    # Требование 5 постановки, и это структурный контроль того же рода, что
    # уже стоит у превью (баг 1.11, `"на кликаемых карточках нет событий,
    # стреляющих внутри клика"` выше в этом файле): `pushEvent` из хука метит
    # СВОЙ элемент `data-phx-ref-src`, поэтому его нельзя вешать на то же,
    # что несёт `phx-click`. `Phoenix.LiveViewTest` не исполняет JS и не
    # проверит клик живьём — это сделано CDP-прогоном отдельно, а здесь
    # закреплена ПРИЧИНА, по которой он обязан пройти: чекбокс галочки не
    # делит DOM-узел ни с одной кликаемой карточкой.
    test "галочка — отдельный узел, а не часть кликаемой карточки", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # ⚠️ Не сравниваем значение `phx-hook` буквально: колокейтед-хук
      # `.GuidedMode` в отрисованном HTML разворачивается в полное имя модуля
      # (`BuildCalculatorWeb.BuilderLive.GuidedMode`), а не остаётся `.
      # GuidedMode`, — тот же приём, каким соседний структурный тест выше
      # («на кликаемых карточках нет событий, стреляющих внутри клика»)
      # проверяет `#preview-bus[phx-hook]` без значения.
      assert has_element?(view, "#guided-toggle-input[phx-hook]")
      refute has_element?(view, "[phx-click]#guided-toggle-input")
      refute has_element?(view, "#race-card-human[phx-hook]")
      refute has_element?(view, "#class-card-fighter[phx-hook]")
    end

    # Задача 3.162: закрытие последнего решения уровня переводит гид на
    # следующий, ЕСЛИ это фронтир билда — тот самый «попадаем сразу на
    # следующий уровень», о котором просил Dan. Elf, а не Human — та же
    # причина, что у соседних тестов guided mode: у Elf нет расового
    # фит-слота 1-го уровня, значит на уровне ровно два слота фитов
    # (`general`, `{:class_bonus, :fighter}`), а не три, и «последнее
    # решение» — предсказуемо одно конкретное действие, а не гадание.
    test "закрытие последнего решения на фронтире переводит на следующий уровень", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :chaotic_good,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 18},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # ⚠️ Та же ловушка, что у соседних тестов — билд из одного уровня без
      # `l=` открывает 2-й, ещё пустой (`load_code/2`: `taken + 1`). 1-й, где
      # стоит единственное незакрытое решение, нужен явным кликом.
      view |> element("#level-1") |> render_click()

      # Осушаем патч ЭТОГО перехода (2 → 1) — иначе он остаётся первым
      # неприкосновенным сообщением в почтовом ящике, и финальный
      # `assert_patch/1` ниже (без явного пути) вернёт ЕГО, а не патч
      # настоящего действия теста: `assert_receive` берёт первое совпавшее
      # по типу сообщение, а не последнее (тот же урок, что у соседнего
      # теста про осушение скролла).
      assert_patch(view)

      render_hook(view, "set_guided_mode", %{"value" => true})

      # Положительный контроль на саму фикстуру: незакрытое на уровне —
      # ровно фиты, ничего больше (иначе «последнее решение» было бы неверной
      # посылкой теста, а не свойством фикстуры).
      assert has_element?(view, "#stage-nav-feats[data-state='hold']")
      assert has_element?(view, "#stage-title", "Уровень 1")

      view |> element("#feat-ok-blind_fight") |> render_click()

      assert_push_event(view, "scroll_to_section", %{id: "stage-head", block: "nearest"})
      assert has_element?(view, "#stage-title", "Уровень 2")
      assert URI.parse(assert_patch(view)).query =~ "l=2"
    end

    # Задача 3.162, edge case «на капе»: фронтир есть, последнее решение
    # закрывается, но следующего уровня НЕТ — гид обязан остановиться
    # молча, а не упасть и не прыгнуть в никуда. 40 уровней воина, 41-й
    # (кап Сиалы) достраивается этим же кликом.
    test "на капе закрытие последнего решения никуда не переводит", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, ruleset.level_cap - 1),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10}
        )

      # Без `l=` билд открывается на СЛЕДУЮЩЕМ непройденном — здесь это ровно
      # кап (`load_code/2`: `taken + 1`), явный клик по лестнице не нужен.
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      render_hook(view, "set_guided_mode", %{"value" => true})

      assert has_element?(view, "#stage-title", "Уровень #{ruleset.level_cap}")
      assert has_element?(view, "#stage-nav-class[data-state='hold']")

      view |> element("#class-card-fighter") |> render_click()

      # Fighter на 41-м не даёт ни фит-слота, ни прибавки стата (проверено
      # прогоном `Feats.open_slots/3` перед тем, как лечь в тест) — класс
      # закрывает ВСЁ, что на капе ещё оставалось, а не только себя.
      assert has_element?(view, "#class-card-fighter[data-chosen='1']")
      refute_push_event(view, "scroll_to_section", %{})
      assert has_element?(view, "#stage-title", "Уровень #{ruleset.level_cap}")
      assert URI.parse(assert_patch(view)).query =~ "l=#{ruleset.level_cap}"
    end

    # Задача 3.162, edge case «правка раннего уровня»: решение Dan
    # 01.09.2026 дословно — «переходить только если это последний
    # заполненный уровень билда». 2 уровня воина, 1-й ЕЩЁ не закрыт (открыт
    # class_bonus слот), 2-й уже закрыт целиком, то есть фронтир — 2-й.
    # Возврат на 1-й и закрытие ТАМ последнего решения гид молчит.
    test "правка раннего уровня не переводит вперёд, даже закрыв там последнее решение", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :chaotic_good,
          levels: [:fighter, :fighter],
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 18},
          feats: %{
            1 => %{general: :toughness},
            2 => %{{:class_bonus, :fighter} => :great_fortitude}
          }
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Билд из двух уровней без `l=` открывает 3-й (`taken + 1`) — 1-й,
      # где стоит незакрытое решение, нужен явным кликом.
      view |> element("#level-1") |> render_click()

      # Осушаем патч ЭТОГО перехода (3 → 1) той же причиной, что у соседнего
      # теста выше — иначе финальный `assert_patch/1` вернёт его, а не патч
      # настоящего клика.
      assert_patch(view)

      render_hook(view, "set_guided_mode", %{"value" => true})

      assert has_element?(view, "#stage-nav-feats[data-state='hold']")

      view |> element("#feat-ok-blind_fight") |> render_click()

      # Гид молчит целиком: ни скролла, ни перехода — активный уровень
      # остаётся 1-м, хотя решений там больше не осталось (2-й, фронтир
      # билда, этим кликом не тронут вовсе).
      refute_push_event(view, "scroll_to_section", %{})
      assert has_element?(view, "#stage-title", "Уровень 1")
      assert URI.parse(assert_patch(view)).query =~ "l=1"
    end

    # Требование 3.162 («смена состояния, а не прокрутка» — проверить как
    # проверяли саму галочку в 3.157): `l` двигается, `b` — нет. Тот же
    # финальный клик, один раз без гида (остаётся на 1-м) и один раз с гидом
    # (переходит на 2-й) — код билда обязан остаться ОДНИМ И ТЕМ ЖЕ.
    test "переход на следующий уровень не меняет код билда в адресе", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :chaotic_good,
          levels: [:fighter],
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 18},
          feats: %{1 => %{general: :toughness}}
        )

      code = Encoding.encode(build)

      # Оба вида (`off`/`on`) листают билд из одного уровня на 1-й тем же
      # кликом, и оба сначала осушают ЭТОТ патч (2 → 1) — иначе финальный
      # `assert_patch/1` вернул бы его вместо патча настоящего клика ниже
      # (тот же урок, что у двух тестов выше).
      {:ok, off, _html} = live(conn, ~p"/?b=#{code}")
      off |> element("#level-1") |> render_click()
      assert_patch(off)
      off |> element("#feat-ok-blind_fight") |> render_click()
      query_off = URI.parse(assert_patch(off)).query |> URI.decode_query()

      {:ok, on, _html} = live(conn, ~p"/?b=#{code}")
      on |> element("#level-1") |> render_click()
      assert_patch(on)
      render_hook(on, "set_guided_mode", %{"value" => true})
      on |> element("#feat-ok-blind_fight") |> render_click()
      query_on = URI.parse(assert_patch(on)).query |> URI.decode_query()
      assert_push_event(on, "scroll_to_section", %{id: "stage-head"})

      assert query_off["b"] == query_on["b"]
      assert query_off["l"] == "1"
      assert query_on["l"] == "2"
    end

    # Задача 3.162, проверено при разборе КРАЯ, а не заказано постановкой:
    # `drop_level` (кнопка «−») — ЕДИНСТВЕННЫЙ обработчик, что выставляет
    # `:active` ДО прихода в `put_build/2` (см. её же комментарий про
    # «чужие, ещё не обновлённые assigns»), и первая гипотеза при разборе
    # была тревожной: усечение билда может выглядеть как «фронтир и только
    # что закрытое последнее решение» одновременно, и гид толкнёт игрока
    # НАЗАД, на только что убранный уровень. Живым прогоном на билде
    # с невыбранным `Weapon of choice` (Мастер оружия, грант с выбором —
    # CLAUDE.md §6) гипотеза не подтвердилась: `drop_level`'s собственная
    # формула никогда не сажает `:active` НИЖЕ старого фронтира, только на
    # него же или дальше, а такая позиция после усечения всегда пустая —
    # «класс» на ней снова pending, и `guide_advance?/2` не проходит по
    # самому первому условию. Разбор — комментарий у `guide_advance?/2`,
    # там же обе раскладки, которыми это доказано. Тест ниже не ловит
    # регрессию по КОНКРЕТНОМУ числу (какой именно уровень покажется) —
    # он ловит расхождение с БАЗОВОЙ линией: гид не имеет права добавить
    # к `drop_level` ничего, чего у кнопки не было без него.
    test "«−» с включённым гидом ведёт себя так же, как без него", %{conn: conn, ruleset: ruleset} do
      # Мастер оружия даёт `Weapon of choice` на СВОЁМ первом уровне
      # (`granted_feats[1]`) — грант, а не слот, и выбор оружия для него
      # не задан этой фикстурой нарочно: это и есть источник «чужих
      # assigns», которым рисковала первая гипотеза.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :elf,
          alignment: :chaotic_good,
          levels: [:fighter, :fighter, :fighter, :weapon_master],
          base_abilities: %{str: 10, dex: 10, con: 14, int: 10, wis: 10, cha: 18},
          feats: %{
            1 => %{:general => :toughness, {:class_bonus, :fighter} => :blind_fight},
            2 => %{{:class_bonus, :fighter} => :siala_blade_proficiency},
            3 => %{general: :iron_will}
          }
        )

      code = Encoding.encode(build)

      {:ok, off, _html} = live(conn, ~p"/?b=#{code}&l=4")
      off |> element("#drop-level") |> render_click()
      title_off = URI.parse(assert_patch(off)).query

      {:ok, on, _html} = live(conn, ~p"/?b=#{code}&l=4")
      render_hook(on, "set_guided_mode", %{"value" => true})
      on |> element("#drop-level") |> render_click()
      title_on = URI.parse(assert_patch(on)).query

      # Само число — «Уровень 4», не «3»: `drop_level` перечитывает счётчик
      # ДО усечения (`level`), не после, так что кнопка «−» возвращает
      # игрока на ТОТ ЖЕ номер, теперь пустой, а не на предыдущий. Это
      # свойство `drop_level`, а не 3.162 — здесь важно только что guided
      # ON и OFF совпадают, а не какое именно число оба показали.
      assert title_off == title_on
      assert title_off =~ "l=4"

      # ⚠️ Скролл к «section-class» здесь ОЖИДАЕМ и не проверяется на
      # отсутствие: уровень освободился (класс снова не выбран), и это уже
      # обычное поведение within-level `guide_scroll/2` (3.157, не 3.162) —
      # target сменился с «section-feats» на «section-class», что для НЕГО
      # — законный повод довезти вид. Регрессия этого теста — только про
      # НОМЕР уровня, не про сам факт скролла.
    end
  end

  describe "export" do
    test "the dialog renders the canonical block", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#export-button") |> render_click()

      text = render(element(view, "#export-text"))

      assert has_element?(view, "#export-dialog")
      assert text =~ "LEVELING GUIDE"
      assert text =~ "Fighter(1)"
    end

    # Задача 3.146 — жалоба игрока через Dan 30.08.2026, глядя на слитый
    # сиальский гид (3.145): «скрыть фиты, получаемые автоматически… по
    # дефолту можно их спрятать, чтоб UI почище был». Монах 1-го уровня без
    # единого пика — весь контент строки взят из грантов, ровно то, на чём
    # игрок и споткнулся.
    test "переключатель прячет автоматические фиты по умолчанию и возвращает их по клику", %{
      conn: conn
    } do
      ruleset = Data.ruleset!()
      build = Build.new(ruleset_version: ruleset.version, levels: [:monk])

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#export-button") |> render_click()
      text = render(element(view, "#export-text"))

      assert has_element?(view, "#export-granted-checkbox")
      refute text =~ "○"
      refute text =~ "выдан классом"
      assert text =~ "01: Monk(1):"

      view |> element("#export-granted-checkbox") |> render_click()
      text = render(element(view, "#export-text"))

      assert text =~
               "○ Cleave, Flurry of blows, Improved unarmed strike, Stunning fist, Weapon proficiency (simple)"

      assert text =~ "выдан классом"
    end

    # `vanilla`'s two-block shape never carried granted feats at all
    # (`leveling_guide/2` only ever reads `build.feats`) — CLAUDE.md §3: ваниль
    # байт в байт, переключателю в ней нечего переключать, так что он не
    # показывается вовсе, а не показывается и бездействует.
    test "у ванильного билда переключателя автоматических фитов нет вовсе", %{conn: conn} do
      ruleset = Data.ruleset!("vanilla")
      build = Build.new(ruleset_version: ruleset.version, levels: [:fighter])

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#export-button") |> render_click()

      assert has_element?(view, "#export-dialog")
      refute has_element?(view, "#export-granted-checkbox")
    end
  end

  describe "import" do
    # ⚠️ Спрятан флагом `Layouts.import_ui?()` под запуск (задача 3.89, решение
    # Dan 24.08.2026) — интерфейс, не код. Весь этот блок проверяет, что модуль
    # и диалог по-прежнему РАБОТАЮТ, поэтому флаг включён на время блока; за
    # тем, что кнопки и диалога нет по умолчанию, следит `ImportUiTest`.
    setup do
      Application.put_env(:build_calculator, :import_ui, true)
      on_exit(fn -> Application.put_env(:build_calculator, :import_ui, false) end)
      :ok
    end

    # Разбор показывается ДО применения: частично прочитанный билд лучше отказа,
    # но только если видно, что именно не прочиталось (CLAUDE.md §3).
    @pasted """
    Каменный - Fighter(2)
    Гном (Dwarf), Lawful Good
    STR: 16 (16)
    Hitpoints: 764
    LEVELING GUIDE
    01: Fighter(1): Power Attack, Неведомый Фит
    02: Fighter(2)
    """

    defp paste(view, text) do
      view
      |> form("#import-form", %{"import" => %{"text" => text}})
      |> render_submit()
    end

    test "the dialog is closed until it is asked for", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#import-dialog[hidden]")
      view |> element("#import-button") |> render_click()
      refute has_element?(view, "#import-dialog[hidden]")
    end

    test "nothing is applied until the report has been shown", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()

      # Ничего не разобрано — применять нечего.
      assert has_element?(view, "#import-apply[disabled]")
      refute has_element?(view, "#import-report")

      paste(view, @pasted)

      assert has_element?(view, "#import-report")
      assert has_element?(view, "#import-summary")
      refute has_element?(view, "#import-apply[disabled]")
      # И билд всё ещё не тронут.
      assert render(element(view, "#character-level")) =~ "0"
    end

    test "the report names what was read and what was not", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)

      assert render(element(view, "#import-read-levels")) =~ "2"
      assert render(element(view, "#import-read-race")) =~ "Гном"
      assert has_element?(view, "#import-issues")
      assert render(element(view, "#import-issues")) =~ "Неведомый Фит"
    end

    test "the source's own numbers are shown beside ours, never imported", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      view |> element("#import-apply") |> render_click()

      # 764 HP пришли из чужого листа персонажа — у двух уровней воина их быть
      # не может, и калькулятор считает своё.
      assert render(element(view, "#import-compare")) =~ "764"
      refute render(element(view, "#stat-hp")) =~ "764"
    end

    test "accepting the report opens the build in the constructor", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      view |> element("#import-apply") |> render_click()

      assert render(element(view, "#character-level")) =~ "2"
      assert has_element?(view, "#split-fighter")
      assert has_element?(view, "#import-dialog[hidden]")

      # ⚠️ Здесь стояла проверка `#save-build[href*='name=']` — «ссылка на
      # сохранение уносит имя из текста». Кнопка спрятана задачей 3.23, а имя
      # больше нигде на экране не появляется, поэтому проверка переехала в
      # `launch_ui_test.exs` (там флаг включается на время теста), а не исчезла.
      # Здесь остаётся то, что видно и без аккаунтов: билд действительно принят.
      refute has_element?(view, "#save-build")
    end

    test "editing the paste drops a report that no longer describes it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, @pasted)
      assert has_element?(view, "#import-report")

      view
      |> form("#import-form", %{"import" => %{"text" => @pasted <> "\n11: Fighter(5)"}})
      |> render_change()

      refute has_element?(view, "#import-report")
    end

    test "a paste with nothing in it cannot be applied", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#import-button") |> render_click()
      paste(view, "здесь нет никакого билда")

      assert has_element?(view, "#import-apply[disabled]")
    end
  end

  describe "reset" do
    test "clears the build and returns to the creation step", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#reset-button") |> render_click()

      assert render(element(view, "#character-level")) =~ "0"
      assert has_element?(view, "#race-cards")
    end

    # Задача 3.114 (26.08.2026, вопрос О4): «Сброс» необратим (в отличие от
    # «− уровень», который снимает один уровень и обратим повторным
    # добавлением), а полного undo в конструкторе нет. `data-confirm` —
    # клиентское поведение (`window.confirm`), `render_click/1` в
    # LiveViewTest его не проверяет и не блокирует им — это ожидаемо
    # (проверено живьём через CDP: диалог показывается и на десктопном,
    # и на мобильном viewport, Cancel билд не трогает, OK сбрасывает).
    # Тест здесь проверяет то, что действительно наблюдаемо на сервере:
    # атрибут присутствует и называет потерю и необратимость.
    test "reset button carries a data-confirm naming the loss and irreversibility", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      reset_button = render(element(view, "#reset-button"))

      assert reset_button =~ "data-confirm="

      # Не «Вы уверены?» — называет, что именно теряется…
      assert reset_button =~ "Уровни, характеристики и вещи"
      # …и что это необратимо.
      assert reset_button =~ "без возможности отмены"
    end

    # Граница задачи: подтверждение стоит только на «Сброс». «− уровень»
    # снимает ровно один уровень и обратим следующим левелапом — его
    # подтверждение не получает (не входит в задачу 3.114).
    test "drop-level carries no confirmation — dropping one level is reversible", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      refute render(element(view, "#drop-level")) =~ "data-confirm"
    end
  end

  describe "карточка класса считает слоты для КАНДИДАТА" do
    # Баг: слоты считались по классу, УЖЕ выбранному на этом уровне, а не по
    # тому, чью карточку игрок разглядывает. Карточка Fighter на 1-м уровне
    # обещала один фит вместо двух — то есть теряла ровно то, ради чего её и
    # открывают: «взяв воина, получу лишний фит».
    test "у Fighter на 1-м уровне общий слот и бонусный, а у Cleric только общий", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()

      fighter = render(element(view, "#class-card-fighter"))
      assert fighter =~ "общий фит"
      assert fighter =~ "бонус Fighter"

      # Положительный контроль для бага 1.4: на 1-м уровне слот не
      # эпический, и подпись обязана молчать про «эпик» — иначе тест ниже
      # («на эпическом уровне общий слот…») зеленел бы и у реализации,
      # приписавшей пометку всем общим слотам подряд.
      refute fighter =~ "эпик"

      cleric = render(element(view, "#class-card-cleric"))
      assert cleric =~ "общий фит"
      refute cleric =~ "бонус"
    end

    test "выбранный класс не навязывает свои слоты чужим карточкам", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      # Возвращаемся на тот же уровень: класс на нём уже стоит. ⚠️ Задача
      # 3.18: раньше секция была схлопнута в сводку и её раскрывали кликом —
      # теперь она открыта, потому что сама не закрывается.
      view |> element("#level-1") |> render_click()

      # Бонусный слот принадлежит Fighter, а не уровню.
      refute render(element(view, "#class-card-cleric")) =~ "бонус Fighter"
      assert render(element(view, "#class-card-fighter")) =~ "бонус Fighter"
    end

    test "человеку карточка обещает лишний слот расы", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()
      view |> element("#level-1") |> render_click()

      assert render(element(view, "#class-card-fighter")) =~ "фит расы"
    end

    test "гному — не обещает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#level-1") |> render_click()

      refute render(element(view, "#class-card-fighter")) =~ "фит расы"
    end

    # ⚠️ Баг 1.4 (Dan 03.08.2026): раньше здесь стояло `assert card =~
    # "эпический фит"` и `refute card =~ "общий фит"` — то есть тест САМ
    # закреплял вводящую в заблуждение подпись. После 20-го уровня пул
    # общего слота не заменяется эпическим, а РАСШИРЯЕТСЯ:
    # `FeatSlots.candidates/2` на Fighter даёт 93 обычных фита внутри 146
    # доступных в эпическом общем слоте (перепроверено 04.08.2026, число
    # не изменилось с находки 03.08.2026). «Эпический фит» без слова «общий»
    # читается как «только эпические» и увёл бы игрока от 93 обычных
    # вариантов — тест теперь проверяет обратное: слово «общий» осталось.
    test "на эпическом уровне общий слот остаётся «общим» и получает пометку «эпик»", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Задача 3.69: без расы и мировоззрения ссылка открылась бы (и клик
      # по `#level-21` остался бы) на уже взятом 20-м — тест проверяет
      # именно предстоящий, ещё не взятый эпический уровень.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 20)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-21") |> render_click()

      card = render(element(view, "#class-card-fighter"))
      assert card =~ "общий фит · эпик"
      refute card =~ "эпический фит"
    end

    # Раньше здесь стояла плашка «от класса ×3» и тест требовал её наличия.
    # Решение Дана (02.08.2026) — убрать: число без имён не отвечает ни на
    # «что я получу», ни на «что мне решать», а карточка отвечает на второе.
    # Тест перевёрнут вместе с решением, иначе он закреплял бы отменённое
    # (HANDOFF: «баг может быть закреплён тестом»).
    test "карточка класса не называет выданное — только то, что игрок решает",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()

      card = render(element(view, "#class-card-ranger"))

      refute card =~ "от класса"
      refute has_element?(view, "#class-card-ranger .d.auto")

      # Строка «выбор» при этом на месте: слоты — это и есть решения уровня.
      assert card =~ "общий фит"
    end

    # ⚠️ Баг 1.11: раса и класс выбирались только со ВТОРОГО клика — и только
    # на проде. Превью висело на самих карточках, `phx-focus` порождал событие
    # на `mousedown`, а LiveView молча выбрасывает клик по элементу, у которого
    # ещё не снят `data-phx-ref-src`. Локально ответ успевал прийти за
    # миллисекунду, поэтому баг не воспроизводился на localhost вовсе.
    #
    # Тест структурный: CSS и JS `Phoenix.LiveViewTest` не исполняет, поэтому
    # проверяется не поведение, а его причина — событие на кликаемом элементе.
    test "на кликаемых карточках нет событий, стреляющих внутри клика", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()

      refute has_element?(view, "[phx-click][phx-focus]")
      refute has_element?(view, "[phx-click][phx-blur]")

      # `phx-mouseover` LiveView не слушает вовсе — атрибут был мёртвым.
      refute has_element?(view, "[phx-mouseover]")
      refute has_element?(view, "[phx-mouseout]")

      # ⚠️ Положительные контроли: без них три `refute` выше зеленели бы и на
      # странице, где карточек нет вообще, — а превью обязано остаться живым,
      # просто переехать на шину.
      assert has_element?(view, "#preview-bus[phx-hook]")
      assert has_element?(view, "#class-card-fighter[data-preview-id='fighter']")
      assert has_element?(view, "#race-card-human[data-preview-id='human']")
    end

    test "панель Δ повторяет ту же форму при наведении", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()

      # ⚠️ Через хук, а не `render_focus/1`: превью больше не висит на самой
      # карточке. `phx-focus` там порождал событие внутри клика, и LiveView
      # выбрасывал клик по элементу с неотвеченным `data-phx-ref-src` — на
      # проде это давало «выбор только со второго клика» (баг 1.11).
      render_hook(view, "preview", %{"kind" => "class", "id" => "fighter"})

      chips = render(element(view, "#delta-list"))
      assert chips =~ "общий фит"
      assert chips =~ "бонус Fighter"
    end

    # ⚠️ Решение Дана (03.08.2026): плашки «к стату +1» здесь тоже больше нет.
    # Причина другая, чем у «от класса ×N» выше: прибавка к характеристике
    # даётся раз в 4 уровня ПЕРСОНАЖА, любым классом, — то есть она ОДИНАКОВА
    # у всех карточек на уровне и не отличает Cleric от соседа ни на йоту.
    # Карточка отвечает на «чем этот класс отличается от соседнего», а строка,
    # стоящая одинаково у всех, на этот вопрос ответить не может по построению.
    # Это не значит «прибавка не важна» — в колонке прогрессии (`▲`) она
    # остаётся, там вопрос другой: «что я решаю на этом уровне».
    test "прибавка к характеристике одинакова у всех классов — карточка её не называет",
         %{conn: conn, ruleset: ruleset} do
      # Задача 3.69: раса и мировоззрение — иначе `#level-4` ниже не пускает
      # дальше уже взятого 3-го (`level_ceiling/2`), а тест смотрит именно
      # на новый уровень с прибавкой к характеристике.
      before =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:fighter, :fighter, :fighter]
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(before)}")

      view |> element("#level-4") |> render_click()

      # У Cleric на уровне 4 ядро не даёт ни одного слота фита — есть только
      # прибавка (проверено `FeatSlots.at/3`: `[]`). Строка «выбор» обязана
      # исчезнуть ЦЕЛИКОМ, а не остаться на карточке пустой.
      cleric = render(element(view, "#class-card-cleric"))
      refute cleric =~ "к стату"
      refute has_element?(view, "#class-card-cleric [data-row='choice']")

      # Положительный контроль в одну сторону: строка «выбор» не пропала
      # из механизма вообще — у Fighter на этом же уровне бонусный слот
      # никуда не делся, значит выше пропала именно пустая строка.
      fighter = render(element(view, "#class-card-fighter"))
      assert fighter =~ "бонус Fighter"
      assert has_element?(view, "#class-card-fighter [data-row='choice']")

      # Положительный контроль в другую сторону: колонка прогрессии
      # по-прежнему знает про прибавку — плашку убрали только с карточки,
      # а не из модели вообще (иначе этот тест зеленел бы и по ошибке).
      assert has_element?(view, "#level-4 .lv-feat[data-abil='1']")

      # И панель Δ говорит ровно то же, что карточка — той же формой
      # (`choice_chips/3` общая для обеих): при наведении она тоже не
      # называет прибавку к характеристике.
      render_hook(view, "preview", %{"kind" => "class", "id" => "cleric"})
      refute render(element(view, "#delta-list")) =~ "к стату"
    end
  end

  describe "фиты, которые класс выдаёт сам" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-ranger") |> render_click()
      view |> element("#level-1") |> render_click()
      %{view: view}
    end

    # Решение Дана 02.08.2026: колонка отвечает на вопрос «что я решил»,
    # а выданное решением не является — повлиять на него нельзя, а место оно
    # занимало наравне с выбором. У монаха это ~18 строк на 20 уровней.
    test "в колонке прогрессии их НЕТ — она показывает только решения", %{view: view} do
      refute has_element?(view, "#lv1-granted-toughness")
      refute has_element?(view, "#lv1-granted-trackless_step")
      refute has_element?(view, "#lv1-granted-dual_wield_feat")
      refute has_element?(view, "#level-1 .lv-feat[data-granted='1']")

      # Слоты при этом на месте: они-то решение и есть — и названы по-разному,
      # потому что бонусный слот Ranger примет только фит из списка Ranger.
      assert has_element?(view, "#lv1-slot-general", "общий фит")
      assert has_element?(view, "#lv1-slot-class_bonus-ranger", "фит Ranger")
    end

    test "в секции фитов они стоят строкой «Класс даёт сам»", %{view: view} do
      assert has_element?(view, "#granted-note")
      assert render(element(view, "#granted-names")) =~ "Toughness"
      assert render(element(view, "#granted-note")) =~ "тратить не нужно"
    end

    # Задача 1.10 шаг 4 (08.08.2026): у воина 1-го уровня семь владений,
    # доехавших до `granted_feats` шагом 3, схлопывали строку в сплошной
    # абзац. Ranger (сценарий блока выше) не показывает разницу — у него
    # только два яруса брони; воин получает все три, это и есть кейс,
    # ради которого задача заведена.
    test "владения одной линейки сворачиваются в блоки, а не в сплошной абзац", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-1") |> render_click()

      document = render(element(view, "#granted-note")) |> LazyHTML.from_fragment()
      items = document |> LazyHTML.query(".granted-item") |> Enum.map(&LazyHTML.text/1)

      # Четыре блока, не шесть строк: три яруса брони свёрнуты в одно имя,
      # `Shield proficiency`, `Weapon proficiency (simple)` и `Toughness`
      # остаются как были. Ни одно из шести исходных имён не пропало — каждое
      # либо цело, либо стоит внутри скобок.
      #
      # ⚠️ Оружейная строка здесь ОДНА, а не свёрнутая пара. Здесь стояло
      # «оружейной строки БОЛЬШЕ НЕТ: замер H5 выключил ванильные владения
      # оружием на Сиале» — верно про `martial`, неверно про `simple`: его
      # шард не выключал, а выдаёт всем классам (задача 3.112, 26.08.2026).
      # Свёртка ДВУХ ярусов оружия в одну скобку жива и проверена на ванильном
      # ruleset'е (`builder/feats_test.exs`), где выдаются оба.
      assert items == [
               "Armor proficiency (light/medium/heavy)",
               "Shield proficiency",
               "Weapon proficiency (simple)",
               "Toughness"
             ]
    end

    test "ступень выдачи видна — иначе строка повторяется из уровня в уровень", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Defensive awareness Защитник получает на 2, 5 и 10 уровнях класса.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          levels: List.duplicate(:fighter, 4) ++ List.duplicate(:dwarven_defender, 5)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#level-6") |> render_click()
      assert render(element(view, "#granted-names")) =~ "Defensive awareness I"

      view |> element("#level-9") |> render_click()
      assert render(element(view, "#granted-names")) =~ "Defensive awareness II"
    end

    test "ступень со своим именем не дописывается к имени фита", %{
      conn: conn,
      ruleset: ruleset
    } do
      # `barbarian_rage` на 15-м уровне — это «greater rage (4x/day)».
      # Наивная склейка дала бы «Barbarian rage greater rage (4x/day)».
      build =
        Build.new(
          ruleset_version: ruleset.version,
          alignment: :chaotic_good,
          levels: List.duplicate(:barbarian, 15)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-15") |> render_click()

      names = render(element(view, "#granted-names"))

      assert names =~ "Greater rage (4x/day)"
      refute names =~ "Barbarian rage greater rage"
    end

    test "строка «Класс даёт сам» называет выданное со ступенями",
         %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          alignment: :chaotic_good,
          levels: [:barbarian, :barbarian]
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      view |> element("#level-2") |> render_click()

      # Со ступенью: `Uncanny dodge I` на 2-м уровне варвара — это не та же
      # строка, что `II` дальше по лестнице. Проверка переехала сюда с плашки
      # карточки: имена теперь живут только здесь.
      #
      # На таком уровне решать нечего — и выданное обязано быть названо прямо
      # в сводке шапки, иначе убранная плашка действительно унесла бы
      # информацию с экрана. ⚠️ Задача 3.18: сводка проверяется по-прежнему,
      # но секция при этом больше не свёрнута — тем полезнее, что сводка
      # называет выданное и в открытом виде тоже.
      assert render(element(view, "#section-feats-toggle")) =~ "Uncanny dodge I"
      assert render(element(view, "#granted-names")) =~ "Uncanny dodge I"
    end

    # 🔴 Баг 1.14 (Dan 10.08.2026): «если файтер дал фиты какие-то, а потом их же
    # дал DD, то в реальности на момент получения DD эти фиты уже дал файтер и на
    # DD мы просто ничего не получили вместо них, они уже есть». Строка «Класс
    # даёт сам» печатала сырую выдачу классового уровня, поэтому первый уровень
    # Защитника называл шесть имён, а нового приносил одно.
    #
    # ⚠️ ОБЕ половины под одним тестом: «дубль не печатается» зеленеет и на голой
    # разности множеств, которая заодно съедает законные ступени, а «ступень
    # печатается» зеленеет на сыром списке, который и есть починяемый баг.
    #
    # ⚠️ Уровни считаны из кода референсного билда Dan, а не из подписи «Воин 10
    # / ДД 23 / ВМ 7»: лестница там не монотонна, а первый уровень Защитника
    # стоит на десятом.
    test "«Класс даёт сам» называет прирост владения, а не сырую выдачу класса", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 9) ++ List.duplicate(:dwarven_defender, 10)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Половина первая: на первом уровне Защитника из шести имён остаётся одно.
      view |> element("#level-10") |> render_click()
      names = render(element(view, "#granted-names"))

      assert names =~ "Defensive stance"
      refute names =~ "Toughness"
      refute names =~ "Armor proficiency"
      refute names =~ "Shield proficiency"

      # Сводка шапки читает тот же список, значит и она перестала врать —
      # а на уровне без слотов это единственное место, где выданное названо
      # поимённо (CLAUDE.md §6).
      summary = render(element(view, "#section-feats-toggle"))
      assert summary =~ "Defensive stance"
      refute summary =~ "Toughness"

      # И третья поверхность того же списка — счётчик в описании уровня.
      # «○ 6 от класса» обещало шесть приобретений там, где их одно.
      assert render(element(view, "#stage-sub")) =~ "○ 1 от класса"

      # Положительный контроль к трём `refute`: на 1-м уровне воин те же самые
      # владения выдаёт по-настоящему, и там они на месте.
      view |> element("#level-1") |> render_click()
      first = render(element(view, "#granted-names"))
      assert first =~ "Toughness"
      assert first =~ "Armor proficiency"

      # Половина вторая: `Defensive awareness` I/II/III — один id трижды
      # (одна страница вики на семейство), и разность множеств оставила бы
      # только первую ступень.
      for {level, step} <- [{11, "I"}, {14, "II"}, {19, "III"}] do
        view |> element("#level-#{level}") |> render_click()

        assert render(element(view, "#granted-names")) =~ "Defensive awareness #{step}",
               "уровень #{level}: ступень Defensive awareness #{step} пропала"
      end
    end

    test "уровень без слотов, но с выданным фитом всё равно показывает секцию", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса — иначе переход на 2-й уровень ниже недоступен;
      # Monk и так требует Lawful, поэтому мировоззрение здесь не любое.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-monk") |> render_click()

      # Monk 2 не выбирает ничего и всё равно получает Deflect Arrows.
      # На 1-м уровне остаёмся: там висит невыбранный общий фит. А со 2-го
      # переход срабатывает сам — решать на нём нечего, — так что смотреть
      # на него надо вернувшись.
      view |> element("#level-2") |> render_click()
      view |> element("#class-card-monk") |> render_click()
      view |> element("#level-2") |> render_click()

      # Тратить нечего, но секция стоит и называет выданное в сводке шапки.
      # ⚠️ Задача 3.18: сворачивания больше нет, раскрывать обратно нечего.
      assert has_element?(view, "#section-feats")
      assert render(element(view, "#section-feats-toggle")) =~ "Deflect arrows"

      assert render(element(view, "#granted-names")) =~ "Deflect arrows"
      refute has_element?(view, "#slot-chips")
      refute has_element?(view, "#feat-lists")

      # А в колонке второй уровень пуст: решений на нём нет.
      refute has_element?(view, "#lv2-granted-deflect_arrows")
      refute has_element?(view, "#level-2 .lv-feats")
    end
  end

  describe "не предлагаем то, что и так дадут" do
    test "Toughness, выданный на этом же уровне, уходит в недоступные с причиной", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()
      view |> element("#level-1") |> render_click()

      # Сиала выдаёт Toughness восьми классам на 1-м уровне, и это самый частый
      # первый фит в NWN — потратить на него общий слот значит купить даром
      # выдаваемое (CLAUDE.md §6).
      refute has_element?(view, "#feat-ok-toughness")
      assert render(element(view, "#feat-no-toughness")) =~ "выдаёт его на этом уровне"
    end

    test "выданное на прошлых уровнях больше не предлагается", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 3)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-3") |> render_click()

      refute has_element?(view, "#feat-ok-toughness")
      assert render(element(view, "#feat-no-toughness")) =~ "уже есть у персонажа"
    end

    test "монаху не продают Cleave, который он получает на первом уровне", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-monk") |> render_click()
      view |> element("#level-1") |> render_click()

      refute has_element?(view, "#feat-ok-cleave")
      assert has_element?(view, "#feat-no-cleave")
    end

    test "фит, который билд выдаст даром позже, помечен предупреждением", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Monk 2 выдаёт Deflect arrows сам. Взять его на 1-м уровне можно — но
      # это трата слота на то, что и так придёт.
      #
      # ⚠️ Было `Ranger 9` / `Improved two-weapon fighting` — источник 4
      # (AGENT_QUEUE.md §1.10) добавил этот фит в `ranger.unavailable_feats`
      # («cannot be selected when gaining a ranger level, even prior to
      # receiving it automatically» — страница фита прямо запрещает то, что
      # этот тест проверял), и `#feat-no-free-improved_two_weapon_fighting`
      # перестал существовать вовсе: фит больше не в одном из двух списков,
      # он не в НИ ОДНОМ. Заменено на `Deflect arrows` / `Monk 2` — тот же
      # паттерн («заблокирован требованиями, но предупреждение есть»), монах
      # его не запрещает.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:monk, 9)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()

      # ⚠️ Проверка стоит на строке НЕдоступного, и это не послабление.
      # На 1-м уровне у монаха DEX 10 — своего требования (DEX 13) фит не
      # набирает, и ядро его отбивает. Предупреждение при этом обязано
      # остаться: оно про ФИТ, а не про сегодняшнюю доступность, и игрок,
      # который дотянет требования, должен узнать про бесплатную выдачу
      # ДО того, как потратит слот.
      warning = render(element(view, "#feat-no-free-deflect_arrows"))

      assert warning =~ "бесплатно"
      assert warning =~ "Monk 2"
      assert warning =~ "уровень 2"

      # И причина отказа названа — недоступное не прячется (CLAUDE.md §6).
      assert render(element(view, "#feat-no-deflect_arrows")) =~ "нужен"
    end

    test "на том, что уже есть, предупреждения нет — платить больше не за что", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:ranger, 9)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()

      refute has_element?(view, "#feat-free-toughness")
      refute has_element?(view, "#feat-no-free-toughness")
    end

    # ⚠️ HANDOFF §A.3, решение Дана 02.08.2026. До сюда предупреждение работало
    # только «на предложении» (см. тест выше): билд, УЖЕ сохранённый со слотом,
    # потраченным на то, что придёт даром, показывался просто «✓ взят» — без
    # единого слова о том, что слот можно освободить. Билд закодирован в URL
    # заранее, ровно как открылась бы чужая ссылка: это не «игрок только что
    # нажал», а «уже собранный билд», для которого и заведён этот тест.
    # ⚠️ Было `Ranger 9` / `Improved two-weapon fighting`. Источник 4
    # (AGENT_QUEUE.md §1.10) добавил этот фит в `ranger.unavailable_feats` —
    # «Ranger 9» больше не может «легально» держать его в общем слоте, слот
    # с ним превратился бы в нелегальный уровень, а этот тест проверяет
    # ровно ОБРАТНОЕ (легально взятое раньше выдачи). Заменено на
    # `Deflect arrows` / `Monk 2`: тот же паттерн («слот занят раньше
    # автовыдачи, и это законно»), монах фит не запрещает.
    test "билд, УЖЕ сохранённый с фитом, который класс всё равно отдал бы даром — показан «взят», но с пометкой",
         %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:monk, 9))
        |> Build.put_feat(1, :general, :deflect_arrows)

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()

      # ⚠️ Задача 3.18: здесь стоял клик по `#section-feats-toggle`. Секция
      # с единственным заполненным слотом (Monk 1) считалась «готовой» и
      # сворачивалась сама — «готовое не занимает экран» (CLAUDE.md §6), — и
      # её приходилось разворачивать, чтобы строка фита вообще была в DOM.
      # Сворачивания больше нет; `section_pending?/2` для "feats" по-прежнему
      # возвращает `false` на этом уровне, но теперь это значит только «экран
      # сюда не подвозим», а не «спрятать».

      # Строка живёт среди ДОСТУПНЫХ, не недоступных: слот потрачен легально,
      # взять фит раньше его выдачи — законный выбор (CLAUDE.md §6).
      row = element(view, "#feat-ok-deflect_arrows")
      assert render(row) =~ "✓ взят"

      # Текст — уже не «на предложении»: «не трать слот» нечего больше
      # советовать, слот УЖЕ потрачен. Отдельная строка с советом до взятия
      # (тест выше) доказывает, что фразы разные, а не что эта пропала вовсе.
      assert render(row) =~ "слот можно освободить"
      assert render(row) =~ "Monk 2"
      refute render(row) =~ "не трать слот"

      # Строка помечена и структурно — не только текстом внутри неё; на это
      # опирается CSS-маркер (второй глиф `○` рядом с `✦`).
      assert has_element?(view, "#feat-ok-deflect_arrows[data-wasted='1']")

      # Тот же факт виден и в колонке прогрессии, рядом с уже принятым
      # решением, а не вместо него: слот по-прежнему называет фит.
      assert has_element?(view, "#lv1-slot-general[data-wasted='1']")
      assert render(element(view, "#lv1-slot-general")) =~ "Deflect arrows"
    end

    # ⚠️ Волна 14 (09.08.2026): то же предупреждение про ВЕЩЬ, и это второй
    # источник «даром», а не второй механизм. До правки строка вообще не
    # доходила до доступных — фит с вещи уезжал в «Недоступные» с причиной
    # «уже есть у персонажа», то есть отказом.
    test "фит, который уже лежит на вещи, предлагается — с оговоркой, а не с отказом", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Волшебник: `Toughness` ему не выдаёт ни класс, ни раса, поэтому
      # в строке виден ровно вклад объявления.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
          gear: BuildCalculator.Rules.Gear.new(feats: [:toughness])
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-3") |> render_click()

      # Строка среди ДОСТУПНЫХ: слот потратить можно — предмет снимается,
      # а слот нет.
      assert has_element?(view, "#feat-ok-toughness")
      refute has_element?(view, "#feat-no-toughness")

      note = render(element(view, "#feat-gear-toughness"))
      assert note =~ "с вещи"
      assert note =~ "снимешь предмет"
    end

    # И вторая половина: слот уже потрачен — оговорка обязана дожить до
    # загруженного билда, включая колонку прогрессии.
    test "слот, потраченный на фит, который есть с вещи, помечен и в строке, и в колонке", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:wizard, 3),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10},
          gear: BuildCalculator.Rules.Gear.new(feats: [:toughness])
        )
        |> Build.put_feat(1, :general, :toughness)

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()

      assert render(element(view, "#feat-ok-toughness")) =~ "✓ взят"
      assert has_element?(view, "#feat-ok-toughness[data-wasted='1']")
      assert has_element?(view, "#lv1-slot-general[data-wasted='1']")
      assert render(element(view, "#lv1-slot-general")) =~ "Toughness"
    end
  end

  describe "карточка класса не теряет маркер решения" do
    # Monk — единственный класс с тремя хорошими сейвами, поэтому даёт шесть
    # числовых плашек против четырёх у остальных. При слепой обрезке списка
    # выпадали «СП» и «фит» — и карточка читалась как «монах не получает фит
    # на первом уровне», хотя слот у него есть (FeatSlots.at даёт :general).
    test "у монаха на 1-м уровне виден фит, как и у всех", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # монах требует Lawful — без мировоззрения карточка заблокирована
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      card = render(element(view, "#class-card-monk"))

      assert card =~ "фит"
      assert card =~ "Will"
      assert card =~ "Ref"
    end
  end

  describe "слоты фитов в колонке названы по-разному" do
    # ⚠️ Слоты НЕ взаимозаменяемы: бонусный тратится только на фит из списка
    # своего класса. До этого у воина на 1-м уровне стояли две одинаковые
    # строки «✦ выбрать фит», и ограничение, из-за которого потом собирается
    # нелегальный билд, на экране не появлялось вовсе (CLAUDE.md §6).
    test "общий и бонусный слот отличаются и текстом, и глифом", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#lv1-slot-general", "общий фит")
      assert has_element?(view, "#lv1-slot-class_bonus-fighter", "фит Fighter")

      # Глиф несёт ту же разницу: у заполненного слота имя фита занимает
      # строку целиком, и кроме глифа сказать «какой это был слот» нечему.
      assert has_element?(view, "#lv1-slot-general", "✦")
      assert has_element?(view, "#lv1-slot-class_bonus-fighter", "⚔")

      # Бонусный помечен и для CSS — он красится в цвет своего класса.
      assert has_element?(view, "#lv1-slot-class_bonus-fighter[data-bonus='1']")
      refute has_element?(view, "#lv1-slot-general[data-bonus='1']")
    end

    test "расовый слот человека — третья строка со своим именем", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-human") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#lv1-slot-general", "общий фит")
      assert has_element?(view, "#lv1-slot-racial", "фит расы")
      assert has_element?(view, "#lv1-slot-class_bonus-fighter", "фит Fighter")
    end

    # ⚠️ У эпического бонусного слота ДРУГОЙ пул: он берёт эпические фиты
    # класса, обычный их не принимает. Назывались они одинаково — «Бонус
    # Fighter», — и 24-й уровень было не отличить от 2-го.
    test "эпический классовый слот назван эпическим и в лестнице, и в чипе", %{
      conn: conn,
      ruleset: ruleset
    } do
      code = Encoding.encode(fighter_41(ruleset))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> element("#level-24") |> render_click()

      assert has_element?(view, "#lv24-slot-class_bonus-fighter", "эпик")
      assert has_element?(view, "#slot-chip-class_bonus-fighter", "эпик")

      # А обычный бонусный слот эпическим не назван — иначе разницы снова нет.
      refute has_element?(view, "#lv2-slot-class_bonus-fighter", "эпик")

      # Общий эпический пользуется той же системой и своим глифом ★.
      assert has_element?(view, "#lv24-slot-general", "★")
      assert has_element?(view, "#lv3-slot-general", "✦")
    end

    # ⚠️ Баг 1.4 (Dan 03.08.2026): у общего слота та же ловушка, что чинилась
    # у бонусного выше, только наоборот — его пул после 20-го НЕ заменяется
    # эпическим, а РАСШИРЯЕТСЯ (`FeatSlots.candidates/2` на Fighter: 93
    # обычных фита остаются доступны и в эпическом общем слоте из 146).
    # «Эпический фит» без слова «общий» читался бы как «только эпические»
    # и сузил бы пул, который на экране обязан выглядеть шире, а не уже.
    test "эпический общий слот остаётся «общим» и в лестнице, и в чипе", %{
      conn: conn,
      ruleset: ruleset
    } do
      code = Encoding.encode(fighter_41(ruleset))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> element("#level-21") |> render_click()

      assert has_element?(view, "#lv21-slot-general", "общий фит · эпик")
      assert has_element?(view, "#slot-chip-general", "эпик")
      refute has_element?(view, "#lv21-slot-general", "эпический фит")

      # Положительный контроль на ту же ловушку, что и в тесте выше:
      # до 20-го уровня пометки нет.
      refute has_element?(view, "#lv18-slot-general", "эпик")
    end
  end

  # ⚠️ Задача 3.30 (решение Dan 15.08.2026): АВТОПЕРЕХОДА БОЛЬШЕ НЕТ. Раздел
  # назывался «не перескакиваем на следующий уровень, пока уровень не закрыт»
  # и держал обе половины прежнего договора: не переходим, пока держит, и
  # переходим сами, как только отпустило. Вторая половина снята вместе
  # с `settle/2` — «принудительный скролл в следующую секцию не понравился»
  # (тестировщик Dan), а автопереход был вторым таким же движением.
  #
  # Что осталось под тестом и почему это не «тест ни о чём»:
  #
  #   * `level_settled?/3` жив и работает — он теперь красит ленту секций
  #     и питает `hold_note/4`, то есть «что держит уровень» по-прежнему
  #     считается и по-прежнему обязано быть верным;
  #   * путь вперёд обязан сохраниться — иначе снятие автоперехода заперло бы
  #     игрока на первом уровне. Проверяется прямо: кликом по `#stage-nav-next`
  #     и двумя уровнями подряд.
  describe "уровень не закрывается сам и не перескакивает (задача 3.30)" do
    # Раньше выбор класса сам перебрасывал вперёд, и решения уровня — фиты,
    # прибавка к характеристике — оставались позади незакрытыми.
    test "выбор класса оставляет на уровне, пока есть пустой слот фита", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 1")
      assert has_element?(view, "#stage-hold")
      assert has_element?(view, "#stage-hold-what", "Общий")
      assert has_element?(view, "#stage-hold-what", "Бонус Fighter")
    end

    test "выбор последнего фита закрывает уровень, но никуда не переводит", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: без расы и мировоззрения переход в конце теста
      # недоступен вовсе — они здесь не предмет теста, поэтому закрываются
      # сразу. ⚠️ Дварф, а не человек: у человека есть СВОЙ дополнительный
      # слот фита 1-го уровня (`extra_feats`, «фит расы») — с ним «выбор
      # последнего фита» означало бы третий фит, а тест закрывает ровно два.
      view |> element("#race-card-dwarf") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      # Alertness ложится в общий слот, Blind fight — в бонусный Fighter:
      # слот выбирается самый узкий подходящий (CLAUDE.md §6).
      view |> element("#feat-ok-alertness") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 1")
      assert has_element?(view, "#stage-hold-what", "Бонус Fighter")
      refute has_element?(view, "#stage-hold-what", "Общий")

      view |> element("#feat-ok-blind_fight") |> render_click()

      # ⚠️ Здесь стояло «Уровень 2» — автопереход. Его больше нет: закрытый
      # уровень остаётся на экране, и правка сделанного выбора не требует
      # возврата назад.
      assert has_element?(view, "#stage-title", "Уровень 1")
      refute has_element?(view, "#stage-hold")

      # Держать нечем — значит и предупреждения на кнопке перехода нет,
      # а сам переход на месте и работает.
      refute has_element?(view, "#stage-nav-next[data-hold='1']")
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")
    end

    # 🔴 Ровно то, чем снятие автоперехода могло всё сломать: если бы вперёд
    # вёл только он, игрок остался бы заперт на первом уровне навсегда.
    test "путь вперёд не пропал: два уровня подряд кликом по ленте", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Пока класса на уровне нет, шагать некуда — и об этом сказано словами,
      # а не молчаливой серой кнопкой (CLAUDE.md §6).
      assert has_element?(view, "#stage-nav-next[data-disabled='1']")
      assert has_element?(view, "#stage-nav-next-why")

      # Задача 3.69: раса и мировоззрение — они здесь не предмет теста,
      # поэтому закрываются сразу, до класса.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()

      view |> element("#class-card-fighter") |> render_click()
      refute has_element?(view, "#stage-nav-next[data-disabled='1']")

      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")

      view |> element("#class-card-fighter") |> render_click()
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 3")
    end

    # На капе шагать некуда — кнопки нет вовсе. Это единственный случай,
    # когда её отсутствие не спрятанная недоступность, а отсутствие цели.
    test "на капе перехода в ленте нет", %{conn: conn, ruleset: ruleset} do
      build = Build.new(ruleset_version: ruleset.version, levels: List.duplicate(:fighter, 41))
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert has_element?(view, "#stage-title", "Уровень 41")
      refute has_element?(view, "#stage-nav-next")
    end

    # ⚠️ Уровень, кратный четырём, у Cleric не даёт ни одного слота фита —
    # только прибавку к характеристике. Если бы её не ждали, игрок оставался
    # бы на пустом с виду уровне; если бы ждали, но не переходили по её
    # выбору — застревал бы на нём насовсем.
    test "уровень с одной только прибавкой к стату держит её, и лента это красит", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса и мировоззрение — не предмет теста, закрываются
      # сразу, иначе четыре последующих перехода недоступны вовсе.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      # Задача 3.14: у Cleric на 1-м уровне класса тоже есть, что решить —
      # два домена. Не то, что проверяет этот тест (прибавка к стату на
      # уровне без слотов фитов, дальше), поэтому закрываем его сразу и
      # молча — без домена уровень 1 держал бы точно так же, но по другой
      # причине, и тест перестал бы проверять то, что заявлен проверять.
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})
      view |> element("#feat-ok-alertness") |> render_click()

      # ⚠️ Задача 3.30: каждый шаг вперёд теперь делает игрок. Раньше здесь
      # стояли голые `assert «Уровень N»` — экран уезжал сам.
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")

      # На 2-м решать нечего вообще: класс выбран — уровень закрыт.
      view |> element("#class-card-cleric") |> render_click()
      refute has_element?(view, "#stage-nav-next[data-hold='1']")
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 3")

      view |> element("#class-card-cleric") |> render_click()

      # AGENT_QUEUE.md §1.10 шаг 3: Cleric владеет лёгкой/средней/тяжёлой
      # бронёй, щитом и простым оружием даром с 1-го уровня — `armor_
      # proficiency_light` подобранный здесь фит с тех пор блокируется как
      # «уже есть у персонажа», а не берётся общим слотом. Toughness Cleric
      # даром не даёт (в список восьми классов CLAUDE.md §3 он не входит),
      # так что он остаётся нейтральным заполнителем слота для этого теста.
      view |> element("#feat-ok-toughness") |> render_click()
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 4")

      # Слотов фитов на нём нет — держит только прибавка.
      view |> element("#class-card-cleric") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 4")
      assert has_element?(view, "#stage-hold-what", "прибавка")
      refute has_element?(view, "#stage-hold-what", "слот")

      # 🔴 Та самая развязка задачи 3.30: прибавка ДЕРЖИТ уровень (янтарь),
      # а навыки на том же экране — только «можно доделать» (сталь).
      assert has_element?(view, "#stage-nav-increase[data-state='hold']")
      assert has_element?(view, "#stage-nav-skills[data-state='todo']")
      assert has_element?(view, "#stage-nav-next[data-hold='1']")

      view |> element("#increase-card-str") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 4")
      assert has_element?(view, "#stage-nav-increase[data-state='done']")
      refute has_element?(view, "#stage-nav-next[data-hold='1']")
    end

    test "снятая прибавка снова держит уровень", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса и мировоззрение — не предмет теста, закрываются
      # сразу, иначе два последующих перехода недоступны вовсе.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      # Задача 3.14: закрываем выбор доменов сразу, тем же доводом, что
      # в тесте выше — этот тест проверяет прибавку к стату, а не домены.
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})
      view |> element("#feat-ok-alertness") |> render_click()
      view |> element("#stage-nav-next") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      view |> element("#stage-nav-next") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      # AGENT_QUEUE.md §1.10 шаг 3: то же самое, что и в тесте выше — Cleric
      # уже владеет бронёй/щитом/простым оружием с 1-го уровня, поэтому
      # заполнителем слота служит Toughness, а не владение.
      view |> element("#feat-ok-toughness") |> render_click()
      view |> element("#stage-nav-next") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      view |> element("#increase-card-str") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 4")
      assert has_element?(view, "#stage-nav-increase[data-state='done']")

      # ⚠️ Задача 3.18: раньше вернувшись на закрытый уровень секцию надо было
      # раскрыть («решённое свёрнуто»). Теперь она открыта сама.
      # ⚠️ Задача 3.30: клик по уже выбранной характеристике снимает её, и
      # уровень снова держит — раньше это же проверяло, что переход НЕ
      # случается от самого факта клика; переходить больше нечему, а
      # «держит» обязано вернуться.
      view |> element("#increase-card-str") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 4")
      assert has_element?(view, "#stage-nav-increase[data-state='hold']")
    end

    # На капе держать нечем: переходить оттуда некуда, и обещание «перейдём
    # дальше сами» было бы обещанием, которого некому исполнить.
    test "на 41-м уровне не держим — дальше некуда", %{conn: conn, ruleset: ruleset} do
      # Задача 3.69: раса и мировоззрение обязательны, чтобы ссылка вообще
      # открылась на «новом» 41-м уровне, а не на уже взятом 40-м — потолок
      # без них не пускает дальше `taken` (`level_ceiling/2`). Без этой пары
      # тест проверял бы совсем другую границу, не капа.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 40)
        )

      code = Encoding.encode(build)
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      assert has_element?(view, "#stage-title", "Уровень 41")
      view |> element("#class-card-fighter") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 41")
      refute has_element?(view, "#stage-hold")
    end

    # Правка готового билда никуда не перебрасывает, как и раньше: «держим»
    # относится только к уровню, который игрок сейчас поднимает.
    test "смена класса на старом уровне не переводит вперёд", %{conn: conn, ruleset: ruleset} do
      code = Encoding.encode(fighter_41(ruleset))
      {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      view |> element("#level-5") |> render_click()

      # ⚠️ Задача 3.18: класс на уровне уже выбран, но секция больше не
      # свёрнута — карточка кликается сразу.
      view |> element("#class-card-cleric") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 5")
      refute has_element?(view, "#stage-hold")
    end

    # ⚠️ Тест ПЕРЕВЁРНУТ 02.08.2026 вместе с решением, а не обойдён.
    #
    # Раньше он утверждал обратное: у Ranger оба неэпических бонусных фита
    # недоступны, слот заполнить нечем, и экран обязан это объяснить. Утверждение
    # было верным, но описывало БАГ: `favored_enemy` отказывал не по правилам,
    # а потому что его требования (`[[ranger]], [[Harper scout]] 1`) лежали
    # непрочитанной прозой, и ядро честно отказывалось проверять фит целиком.
    # Проза дочитана — тупик исчез.
    #
    # ⚠️ Машинерия объяснения тупика ЖИВА, и у неё есть настоящие примеры —
    # просто не на первом уровне. Бонусный слот пуст (кандидатов ровно ноль,
    # весь список класса эпический) у Shadowdancer, Shifter и Pale Master
    # на 13, 16 и 19 уровнях класса, у Assassin и Arcane Archer на 14 и 18.
    #
    # ⚠️ Первая редакция этого комментария утверждала обратное — «ни у одного
    # класса не осталось». Проверено было только на 1-м уровне, а вывод сделан
    # про все. Тот же урок, что с «13 скилл-поинтами» и с «всем семейством
    # Cure *»: сплошную проверку заменять первым попавшимся срезом нельзя.
    #
    # Покрытия через интерфейс у этих случаев нет и оно недёшево: объяснение
    # показывается только пока игрок ПОДНИМАЕТ уровень, а поднять 13 уровней
    # Shadowdancer кликами в тесте — отдельная стройка. Не удаляй машинерию как
    # мёртвый код: она не мертва, она непокрыта.
    test "бонусный слот Ranger'а больше не тупик", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-ranger") |> render_click()

      assert has_element?(view, "#stage-title", "Уровень 1")
      refute has_element?(view, "#stage-hold[data-dead='1']")

      # Положительный контроль: слот действительно предлагает то, ради чего
      # он существует, а не «не тупик, потому что исчез».
      assert has_element?(view, "#feat-ok-favored_enemy")
    end
  end

  describe "фит с параметром: второй шаг" do
    # Билд собирается с нуля, а не грузится из кода: автопереход срабатывает
    # только пока игрок ПОДНИМАЕТ уровень, и на готовом билде проверять его
    # было бы проверкой мимо предмета.
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#race-card-dwarf") |> render_click()

      # ⚠️ Починка чужой фикстуры (координатор волны, не часть задачи про
      # карточку класса). Дварф с нетронутым поинт-баем стартует с INT 8,
      # а ядро после правки агента A (правило «характеристика ≥ 10 + круг»
      # из HANDOFF §A.2) честно отказывает такому магу в касте 1-го круга —
      # нужен INT ≥ 11. Без этого `#feat-ok-spell_focus` не появляется вовсе,
      # и все семь тестов блока падали не из-за багов в UI, а из-за
      # нежизнеспособного билда, который собирает `setup`.
      #
      # ⚠️ Задача 3.17 слила расу и класс в один экран уровня 1 — `#point-buy-int-up`
      # теперь существует и до, и после выбора класса, так что порядок клика
      # ниже больше не единственный рабочий (было не так до слияния: тогда
      # поинт-бай стоял на отдельном «нулевом» экране и пропадал, как только
      # игрок переходил на уровень 1, а клик по несуществующей кнопке валил
      # `setup` целиком). Оставлен как есть — порядок по-прежнему валиден,
      # просто причина держаться его исчезла вместе со вторым экраном.
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()
      view |> element("#point-buy-int-up") |> render_click()

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      # Задача 3.69: без мировоззрения кнопка «Уровень N →» ниже недоступна
      # (раса уже выбрана строкой выше) — один из тестов блока поднимается
      # на 3-й уровень именно через неё.
      view |> element("#alignment-lawful_good") |> render_click()

      %{view: view}
    end

    test "клик по фиту с выбором открывает шаг 2 и НИЧЕГО не пишет в билд", %{view: view} do
      refute has_element?(view, "#feat-choice")

      view |> element("#feat-ok-spell_focus") |> render_click()

      assert has_element?(view, "#feat-choice")
      assert has_element?(view, "#feat-choice-title", "Spell focus")

      # ⚠️ Пик без записанного выбора неотличим от другого такого же, поэтому
      # слот остаётся пустым до ответа — на этом же держится автопереход.
      refute has_element?(view, "#slot-chip-general[data-filled='1']")

      # Список фитов уступил место шагу: два кликабельных списка спорили бы
      # за один слот.
      refute has_element?(view, "#feat-lists")
    end

    # ⚠️ Этот тест НЕ ловит поломку, которая была здесь 02.08.2026, и это
    # написано, чтобы никто не полагался на него как на защиту.
    #
    # Кнопка несла `phx-value-value`, и в браузере выбор не сохранялся: у
    # `<button>` есть собственное свойство `value`, оно пустое, LiveView
    # подмешивает его в параметры и затирает `phx-value-*` — на сервер
    # приходило `%{"value" => ""}`. `Phoenix.LiveViewTest` собирает параметры
    # ТОЛЬКО из `phx-value-*` и родное свойство не воспроизводит, поэтому все
    # тесты вокруг были зелёными при неработающей фиче.
    #
    # Тест ниже проверяет имя параметра напрямую — это единственное, что здесь
    # вообще проверяемо без настоящего браузера.
    test "кнопка выбора не использует имя параметра «value»", %{view: view} do
      view |> element("#feat-ok-spell_focus") |> render_click()

      html = render(element(view, "#feat-choice-evocation"))

      assert html =~ "phx-value-choice"
      refute html =~ "phx-value-value"
    end

    test "выбор значения записывает пару и показывает её везде, где видно имя", %{view: view} do
      view |> element("#feat-ok-spell_focus") |> render_click()
      view |> element("#feat-choice-evocation") |> render_click()

      # Колонка прогрессии — она же лестница.
      assert render(element(view, "#lv1-slot-general")) =~ "Spell focus (Evocation)"
      refute has_element?(view, "#feat-choice")

      # Секция фитов: закрытая — сводкой в шапке, открытая — чипом слота.
      view |> element("#level-1") |> render_click()
      assert render(element(view, "#section-feats")) =~ "Spell focus (Evocation)"

      assert has_element?(view, "#slot-chip-general[data-filled='1']")
      assert render(element(view, "#slot-chip-general")) =~ "Spell focus (Evocation)"
    end

    test "отмена возвращает список и не трогает билд", %{view: view} do
      view |> element("#feat-ok-spell_focus") |> render_click()
      view |> element("#feat-choice-cancel") |> render_click()

      refute has_element?(view, "#feat-choice")
      assert has_element?(view, "#feat-lists")
      refute has_element?(view, "#slot-chip-general[data-filled='1']")
    end

    test "незакрытый шаг 2 держит уровень, закрытый — отпускает", %{view: view} do
      assert has_element?(view, "#stage-title", "Уровень 1")

      view |> element("#feat-ok-spell_focus") |> render_click()

      # Слот пуст, значит уровень не закрыт — и это ТО ЖЕ правило, что держит
      # уровень с невыбранным фитом, а не второе такое же.
      assert has_element?(view, "#stage-title", "Уровень 1")
      assert has_element?(view, "#stage-hold")
      assert has_element?(view, "#stage-nav-feats[data-state='hold']")

      view |> element("#feat-choice-evocation") |> render_click()

      # ⚠️ Задача 3.30: здесь стоял `assert «Уровень 2»` — автопереход.
      # Держать перестало, а экран остался на месте.
      assert has_element?(view, "#stage-title", "Уровень 1")
      refute has_element?(view, "#stage-hold")
      assert has_element?(view, "#stage-nav-feats[data-state='done']")
    end

    test "занятое значение прячется, а недоступное по правилам — показано с причиной",
         %{view: view} do
      # Положительный контроль: до взятия школа в списке есть.
      view |> element("#feat-ok-spell_focus") |> render_click()
      assert has_element?(view, "#feat-choice-evocation")
      view |> element("#feat-choice-evocation") |> render_click()

      # Уровни 2 и 3 у волшебника: слот фита даётся на 3-м.
      # ⚠️ Задача 3.30: раньше выбор класса перебрасывал вперёд сам, и двух
      # кликов по карточке хватало. Автоперехода нет — шаг вперёд делается
      # явно, кнопкой в ленте секций.
      view |> element("#stage-nav-next") |> render_click()
      view |> element("#class-card-wizard") |> render_click()
      view |> element("#stage-nav-next") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      view |> form("#feat-search-form", %{"q" => "spell focus"}) |> render_change()
      view |> element("#feat-ok-spell_focus") |> render_click()

      # Решение Дана (§6): «эту школу ты уже взял» механике не учит.
      refute has_element?(view, "#feat-choice-evocation")
      refute has_element?(view, "#feat-choice-no-evocation")
      assert has_element?(view, "#feat-choice-necromancy")

      view |> element("#feat-choice-cancel") |> render_click()

      # А `Greater spell focus` в школе без базового — это МЕХАНИКА, и она
      # обязана стоять в списке с причиной, а не исчезать.
      view |> form("#feat-search-form", %{"q" => "greater spell focus"}) |> render_change()
      view |> element("#feat-ok-greater_spell_focus") |> render_click()

      assert has_element?(view, "#feat-choice-evocation")
      assert has_element?(view, "#feat-choice-no-necromancy")
      assert render(element(view, "#feat-choice-no-necromancy")) =~ "Spell focus"
    end

    test "выбор доезжает до ссылки и открывается обратно", %{view: view, conn: conn} do
      view |> element("#feat-ok-spell_focus") |> render_click()
      view |> element("#feat-choice-evocation") |> render_click()

      # ⚠️ Код берётся из ссылки на экране, а не из `assert_patch/1`: патчей
      # к этому моменту накопилось несколько (раса, класс, фит), и первый
      # из них описывает билд ДО выбора.
      [_, code] = Regex.run(~r/b\/([^"]+)"/, render(element(view, "#share-link")))
      {:ok, reopened, _html} = live(conn, ~p"/?b=#{code}")

      assert render(element(reopened, "#lv1-slot-general")) =~ "Spell focus (Evocation)"
    end
  end

  describe "счётные фиты: ×N вместо одинаковых строк" do
    test "второе взятие подписано счётчиком, первое — нет", %{conn: conn, ruleset: ruleset} do
      # `Epic toughness` берётся десять раз; десять одинаковых строк в лестнице
      # — та же болезнь, что была у соркерера с шестью «выбрать заклинание».
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{
            21 => %{general: :epic_toughness},
            24 => %{general: :epic_toughness}
          }
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      first = render(element(view, "#lv21-slot-general"))
      assert first =~ "Epic toughness"
      refute first =~ "×"

      assert render(element(view, "#lv24-slot-general")) =~ "Epic toughness ×2"
    end

    test "повторяемый фит остаётся кнопкой «ещё раз», а не гаснет как «взят»", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:fighter, 41),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{21 => %{general: :epic_toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-24") |> render_click()

      view
      |> form("#feat-search-form", %{"q" => "epic toughness"})
      |> render_change()

      assert has_element?(view, "#feat-ok-epic_toughness")
      assert render(element(view, "#feat-ok-epic_toughness")) =~ "взят ×1"

      # ⚠️ Ложится в БОНУСНЫЙ слот воина, а не в общий: `Epic toughness` есть
      # в списке Fighter, и слот выбирается самый узкий подходящий (§6).
      view |> element("#feat-ok-epic_toughness") |> render_click()

      assert render(element(view, "#lv24-slot-class_bonus-fighter")) =~ "Epic toughness ×2"
    end
  end

  describe "правка раннего уровня перепроверяет поздние (задача 1.3)" do
    # Дословный вопрос Dan (03.08.2026): «взяли все фиты для ВМ, набрали
    # уровней ВМ, потом вернулись в начало и заменили один из фитов — что
    # будет с уже взятыми уровнями?». Fighter 1–9 набирает все шесть фитов
    # Weapon Master (`dodge`, `mobility`, `expertise`, `spring_attack`,
    # `weapon_focus`, `whirlwind_attack`) плюс `Intimidate` 4, дальше три
    # уровня самого класса — билд легален целиком, ни одна из шести не лишняя.
    defp weapon_master_ladder_build(ruleset) do
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

    test "снятие фита помечает все уровни Weapon Master, которые он держал — не только первый",
         %{conn: conn, ruleset: ruleset} do
      build = weapon_master_ladder_build(ruleset)
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      # Уровень 1 держит и `dodge` (общий слот), и `weapon_focus` (бонус
      # Fighter). ⚠️ Задача 3.18: секция фитов раньше была свёрнута (оба слота
      # заняты) и её приходилось открывать, чтобы кнопка «✕» появилась в DOM.
      view |> element("#level-1") |> render_click()
      view |> element("#slot-clear-class_bonus-fighter") |> render_click()

      for level <- [10, 11, 12] do
        assert has_element?(view, "#level-#{level}[data-illegal='1']")
        assert has_element?(view, "#level-#{level}-issue")

        text = render(element(view, "#level-#{level}-issue"))
        assert text =~ "Weapon master"
        assert text =~ "Weapon focus"
      end

      # Снятый фит сам по себе не отмечает свой собственный уровень — только
      # то, что от него зависело.
      refute has_element?(view, "#level-1[data-illegal='1']")

      assert render(element(view, "#spine-illegal")) =~ "3"
    end

    # Положительный контроль ко всему разделу (HANDOFF, «пустые проверки»):
    # тот же билд без снятия фита не получает ни одной пометки. Иначе тест
    # выше зеленел бы и в мире, где отметка стоит на каждом уровне подряд.
    test "тот же билд без снятия фита не получает ни одной пометки", %{
      conn: conn,
      ruleset: ruleset
    } do
      build = weapon_master_ladder_build(ruleset)
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      for level <- 1..12 do
        refute has_element?(view, "#level-#{level}[data-illegal='1']")
        refute has_element?(view, "#level-#{level}-issue")
      end

      refute has_element?(view, "#spine-illegal")
    end

    test "смена расы помечает уровни Dwarven Defender, у которых она была требованием", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :dwarf,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 7) ++ List.duplicate(:dwarven_defender, 2),
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 10, cha: 8},
          feats: %{1 => %{:general => :dodge, {:class_bonus, :fighter} => :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      refute has_element?(view, "#level-8[data-illegal='1']")

      # Задача 3.17: `#level-0` теперь ведёт на уровень 1 — там же живёт раса.
      # ⚠️ Задача 3.18: билд пришёл с уже выбранной расой, но секция больше не
      # свёрнута — карточка другой расы кликается сразу.
      view |> element("#level-0") |> render_click()
      view |> element("#race-card-human") |> render_click()

      for level <- [8, 9] do
        assert has_element?(view, "#level-#{level}[data-illegal='1']")
        assert render(element(view, "#level-#{level}-issue")) =~ "Dwarven defender"
      end
    end

    test "смена мировоззрения помечает уровни Monk", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: [:monk, :monk, :monk],
          base_abilities: %{str: 14, dex: 14, con: 12, int: 10, wis: 14, cha: 8}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      refute has_element?(view, "#level-1[data-illegal='1']")

      # Тот же приём, что выше у расы, и та же правка задачи 3.18:
      # мировоззрение уже выбрано во входящем билде, но секция открыта.
      view |> element("#level-0") |> render_click()
      view |> element("#alignment-chaotic_good") |> render_click()

      for level <- [1, 2, 3] do
        assert has_element?(view, "#level-#{level}[data-illegal='1']")
        assert render(element(view, "#level-#{level}-issue")) =~ "Monk"
      end
    end

    # Дыра шире фитов: снятая прибавка к характеристике, от которой зависел
    # порог фита. Ни один класс не требует `abilities` напрямую (только
    # фиты), так что без прогонки уже взятых фитов, а не только классов,
    # этот сценарий остался бы невидимым.
    test "снятая прибавка к характеристике помечает фит, чей порог она держала", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 6),
          base_abilities: %{str: 10, dex: 12, con: 10, int: 10, wis: 10, cha: 8},
          ability_increases: %{4 => :dex},
          feats: %{6 => %{general: :dodge}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      refute has_element?(view, "#level-6[data-illegal='1']")

      view |> element("#level-4") |> render_click()
      view |> element("#increase-card-dex") |> render_click()

      assert has_element?(view, "#level-6[data-illegal='1']")
      text = render(element(view, "#level-6-issue"))
      assert text =~ "Dodge"
      assert text =~ "DEX"
    end
  end

  # 🔴 Найдено разведкой при замере ДРУГОГО запроса Dan (цель наведения
  # `.lv-illegal` в CSS, задача 3.117) — импорт лога не переносит
  # мировоззрение, `nil` перепроверяется на каждом уровне класса и раньше
  # печатал 35 одинаковых значков «Barbarian: нужно не Lawful» у 35-уровневого
  # варвара. `Labels.ladder_issues/2` уже проверена таблицами кейсов; здесь —
  # что это доезжает до DOM конструктора: счётчик в шапке колонки и сама
  # отметка на 1-м уровне.
  describe "невыбранное мировоззрение — одна отметка, а не по одной на уровень (задача 3.117)" do
    test "спайн и отметка 1-го уровня видят ОДНУ причину на 35 уровней варвара без мировоззрения",
         %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: nil,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
          levels: List.duplicate(:barbarian, 35)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert render(element(view, "#spine-illegal")) =~ "1 "

      assert has_element?(view, "#level-1[data-illegal='1']")
      text = render(element(view, "#level-1-issue"))
      assert text =~ "Barbarian"
      assert text =~ "не выбрано"

      # ⚠️ «Не Lawful» остаётся в тексте как деталь того, что понадобится —
      # проверяем отсутствие СТАРОЙ фразы целиком, не подстроки внутри новой.
      refute text =~ "title=\"Barbarian: нужно не Lawful\""

      # Остальные 34 уровня класса не несут СВОЕЙ отметки — причина названа
      # один раз, а не молчанием: `#spine-illegal` выше уже подтвердил,
      # что билд по-прежнему числится нелегальным.
      for level <- 2..35 do
        refute has_element?(view, "#level-#{level}[data-illegal='1']")
      end
    end

    # Часть A той же задачи: цель наведения теперь достижима с клавиатуры,
    # а не только мышью (CLAUDE.md, designer — «ховер не единственный путь»).
    test "значок нарушения фокусируется с клавиатуры и несёт aria-label", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: nil,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
          levels: List.duplicate(:barbarian, 1)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      html = render(element(view, "#level-1-issue"))
      assert html =~ ~s(tabindex="0")
      assert html =~ "aria-label="
      refute html =~ ~s(aria-hidden="true")
    end

    # Положительный контроль: выбранное, но несовместимое мировоззрение
    # остаётся честной отметкой на каждом уровне — сворачивать НАСТОЯЩИЙ
    # конфликт значило бы прятать нарушение (CLAUDE.md §6).
    test "выбранное несовместимое мировоззрение по-прежнему метит каждый уровень", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          base_abilities: %{str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 8},
          levels: List.duplicate(:barbarian, 3)
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      for level <- 1..3 do
        assert has_element?(view, "#level-#{level}[data-illegal='1']")
        assert render(element(view, "#level-#{level}-issue")) =~ "нужно не Lawful"
      end
    end
  end

  describe "выбор класса — домены клирика (задача 3.14)" do
    # «Each cleric chooses two of these domains when the first clerical level
    # is taken» (Fandom, `Domain`) — «первый уровень клирика» это уровень
    # КЛАССА, а не персонажа, что и проверяет второй тест ниже.
    test "клирик первым классом просит выбрать ровно два домена на 1-м уровне", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      assert has_element?(view, "#section-domains")
      assert has_element?(view, "#class-choice-air")
      assert has_element?(view, "#class-choice-war")

      # До выбора это видно как незавершённое: секция раскрыта сама
      # («автораскрытие незавершённых», CLAUDE.md §6) и держит счётчик
      # «не выбрано» в шапке лестницы, ровно как незаполненный слот фита.
      assert has_element?(view, "#section-domains-body")
      assert has_element?(view, "#spine-todo", "не выбрано")

      # Уровень не закрывается только выбором класса, пока домены не названы
      # — даже если бы фитов на этом уровне не было вовсе.
      refute has_element?(view, "#stage-title", "Уровень 2")
    end

    test "выбор двух доменов записывается и виден в колонке прогрессии", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      view
      |> render_click("toggle_class_choice", %{"class" => "cleric", "choice" => "air"})

      assert has_element?(view, "#class-choice-air[data-chosen='1']")
      refute has_element?(view, "#class-choice-war[data-chosen='1']")

      # Решение ещё висит — выбрано только одно из двух. ⚠️ Задача 3.18:
      # раньше это проверялось наличием тела секции (она раскрывалась сама);
      # теперь тело есть всегда, а «ждёт решения» несёт `data-pending`.
      assert has_element?(view, "#section-domains[data-pending='1']")
      assert has_element?(view, "#section-domains-body")

      view
      |> render_click("toggle_class_choice", %{"class" => "cleric", "choice" => "war"})

      # Выбор полный — решение снято. ⚠️ Задача 3.18: секция при этом НЕ
      # сворачивается, чипы остаются в DOM, и передумать можно на месте.
      # Сводка в шапке всё равно называет оба выбора поимённо.
      assert has_element?(view, "#section-domains[data-pending='0']")
      assert has_element?(view, "#section-domains-body")
      assert has_element?(view, "#section-domains", "Air")
      assert has_element?(view, "#section-domains", "War")

      html = render(view)
      assert html =~ "Air"
      assert html =~ "War"

      # Отметка в лестнице — по DOM-id, названному уровнем, а не классом:
      # `#level-1-domains` существует и называет оба выбранных имени.
      assert has_element?(view, "#level-1-domains")
      domains_text = render(element(view, "#level-1-domains"))
      assert domains_text =~ "Air"
      assert domains_text =~ "War"
    end

    test "клик по уже выбранному домену снимает его — переход не проваливается", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})

      refute has_element?(view, "#class-choice-air[data-chosen='1']")
      assert has_element?(view, "#class-choice-war[data-chosen='1']")
      assert has_element?(view, "#section-domains-body")
    end

    test "выбор навсегда — на следующих уровнях клирика больше не спрашивает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: без расы и мировоззрения кнопка «Уровень 2 →» ниже
      # недоступна — тесту нужен переход, а не оценка самой блокировки.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})
      view |> element("#feat-ok-toughness") |> render_click()

      # ⚠️ Задача 3.30: шаг вперёд теперь делает игрок — автоперехода нет.
      view |> element("#stage-nav-next") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")
      view |> element("#class-card-cleric") |> render_click()
      assert has_element?(view, "#stage-title", "Уровень 2")

      # 2-й уровень клирика не открывает секцию доменов вовсе — выбор уже
      # сделан на 1-м, а не переспрашивается на каждом уровне того же класса.
      refute has_element?(view, "#section-domains")
      refute has_element?(view, "#stage-nav-domains")

      # И уровень ничем не держится: класс выбран, слотов на 2-м уровне
      # клирика нет — значит и оставленного решения на переходе нет.
      refute has_element?(view, "#level-2-domains")
      refute has_element?(view, "#stage-nav-next[data-hold='1']")
    end

    # ⚠️ «Первый уровень клирика» — это класс-уровень, а не уровень
    # персонажа. Клирика можно взять пятым классом на 30-м уровне билда
    # (здесь — шестым, для краткости теста), и выбор происходит там же.
    test "клирик не первым классом — выбор происходит на уровне, где он взят, не на 1-м", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса и мировоззрение нужны один раз, до цикла, иначе
      # потолок лестницы не пустит дальше уровня 1 вовсе.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()

      for level <- 1..5 do
        view |> element("#level-#{level}") |> render_click()
        view |> element("#class-card-fighter") |> render_click()
      end

      # Пять уровней воина сами закрываются по мере фитов — довели курсор до
      # уровня 6 руками, а не полагаясь на автопереход между разными классами.
      view |> element("#level-6") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      assert has_element?(view, "#section-domains")
      refute has_element?(view, "#level-1-domains")

      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})

      assert has_element?(view, "#level-6-domains")
      refute has_element?(view, "#level-1-domains")
    end

    # Положительный контроль: без него зелёные тесты выше были бы неотличимы
    # от реализации, которая показывает выбор класса всем подряд.
    test "у обычного класса секции доменов нет вовсе", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-fighter") |> render_click()

      refute has_element?(view, "#section-domains")
      refute has_element?(view, "#level-1-domains")
    end

    # Третий домен не помещается — кап два, а не бюджет без верхней границы.
    test "третий домен не добавляется сверх count — кнопка недоступна", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})

      # ⚠️ Задача 3.18: выбор полный, но секция НЕ свернулась — передумать
      # можно, ничего не раскрывая. Ровно та жалоба Dan, из которой выросла
      # задача: «хочется изменить выбор, а секция уже скрыта».
      assert has_element?(view, "#section-domains-body")

      assert has_element?(view, "#class-choice-fire[disabled]")
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "fire"})

      refute has_element?(view, "#class-choice-fire[data-chosen='1']")
      assert has_element?(view, "#class-choice-air[data-chosen='1']")
      assert has_element?(view, "#class-choice-war[data-chosen='1']")
    end

    # Билд, уже собранный где-то ещё (в частности — старой ссылкой, задача
    # ниже), открывается конструктором таким же: выбор виден, решения на
    # секции не висит, уровень не держит. ⚠️ Задача 3.18: раньше здесь стояло
    # «секция свёрнута (готовое не занимает экран)» — она больше не
    # сворачивается, и проверяется именно `data-pending`, а не наличие тела.
    test "билд с доменами, открытый по ссылке, приходит уже закрытым", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:cleric],
          class_choices: %{cleric: [:air, :war]},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")
      view |> element("#level-1") |> render_click()

      assert has_element?(view, "#section-domains[data-pending='0']")
      assert has_element?(view, "#section-domains", "Air")
      assert has_element?(view, "#level-1-domains")
    end
  end

  describe "кодирование доменов в URL (задача 3.14)" do
    test "билд с доменами кодируется и раскодируется тем же билдом", %{ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:cleric, :cleric],
          class_choices: %{cleric: [:air, :war]}
        )

      assert {:ok, %{build: decoded, dropped: []}} =
               Encoding.decode(Encoding.encode(build))

      assert decoded == build
    end

    # Ссылка предыдущей версии формата (до этой задачи) не несла доменов
    # вовсе — она обязана открыться, а не упасть и не потерять уровни.
    test "старая ссылка без доменов открывается без ошибок", %{conn: conn, ruleset: ruleset} do
      old_build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: List.duplicate(:cleric, 3),
          feats: %{1 => %{general: :toughness}}
        )

      code = Encoding.encode(old_build)
      assert {:ok, view, _html} = live(conn, ~p"/?b=#{code}")

      assert has_element?(view, "#character-level", "3")

      # Сам билд не падает и не теряет уровни — марка на 1-м уровне стоит,
      # но честно показывает «не выбрано» (домены не записывались этим
      # форматом ссылки до задачи 3.14), а не выдумывает, что игрок выбрал.
      assert has_element?(view, "#level-1-domains[data-todo='domain']")
    end

    # Битая ссылка — понятное сообщение и пустой конструктор, не 500.
    test "битая ссылка на билд с классом не роняет LiveView", %{conn: conn} do
      assert {:ok, view, _html} = live(conn, ~p"/?b=not-a-real-code")

      assert has_element?(view, "#builder-header")
      assert has_element?(view, "#character-level", "0")
    end
  end

  describe "выбор класса — школа волшебника (задача 3.10)" do
    # ⚠️ Главное отличие от доменов клирика: выбор НЕОБЯЗАТЕЛЕН, и билд без
    # него легален и завершён. «A wizard does not have to specialize, thus
    # keeping access to all spells» (Fandom «Wizard»).
    test "визард первым классом предлагает школу, но она не держит переход", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      assert has_element?(view, "#section-domains")
      assert has_element?(view, "#class-choice-evocation")

      # «Без специализации» — отсутствие значения, не псевдошкола `universal`
      # (CLAUDE.md §6, AGENT_QUEUE.md §3.10): её не должно быть в списке.
      refute has_element?(view, "#class-choice-universal")

      # Единственное, что держит 1-й уровень волшебника, — общий слот фита.
      # Выбор школы уровень НЕ держит (в отличие от доменов клирика).
      view |> element("#feat-ok-toughness") |> render_click()

      # ⚠️ Задача 3.30: раньше это доказывалось автопереходом («ушли на
      # 2-й, ни разу не щёлкнув по школе»). Автоперехода нет, зато та же
      # разница видна ПРЯМО и на месте: школа висит стальным «можно
      # доделать», а не янтарным «держит уровень», и переход не помечен
      # оставленным решением.
      assert has_element?(view, "#stage-nav-domains[data-state='todo']")
      refute has_element?(view, "#stage-nav-domains[data-state='hold']")
      refute has_element?(view, "#stage-nav-next[data-hold='1']")

      # Положительный контроль: у клирика тот же самый выбор — янтарный.
      {:ok, cleric, _html} = live(conn, ~p"/")
      cleric |> element("#class-card-cleric") |> render_click()
      assert has_element?(cleric, "#stage-nav-domains[data-state='hold']")
    end

    # ⚠️ Находка задачи 3.10: `data-todo="domain"` красит строку лестницы
    # янтарём («не выбрано, надо закрыть») и раньше ставился по одному лишь
    # `missing > 0` — верно для клирика (обязателен), но для необязательного
    # волшебника рисовало бы вечный янтарь на легальном финале «без
    # специализации». Правка — гейт по `required?` в `builder_live.html.heex`;
    # без него эта строка стала бы `data-todo='domain'`.
    test "необязательная незаполненная школа НЕ красится как незавершённая", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Задача 3.69: раса и мировоззрение нужны, чтобы дойти до 2-го уровня
      # ниже, — сами по себе они здесь не проверяются.
      view |> element("#race-card-human") |> render_click()
      view |> element("#alignment-lawful_good") |> render_click()
      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      assert has_element?(view, "#level-1-domains")
      refute has_element?(view, "#level-1-domains[data-todo='domain']")

      # Положительный контроль на этот же тест: та же самая пометка у
      # клирика (обязателен) остаётся амброй — иначе `refute` выше был бы
      # неотличим от полностью снятого атрибута у ЛЮБОГО выбора класса.
      view |> element("#level-2") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      assert has_element?(view, "#level-2-domains[data-todo='domain']")
    end

    # Ключевой сценарий задачи: числа в итогах меняются на СПЕЦИАЛИЗАЦИИ —
    # без выбора школы слот 1-го круга остаётся базовым, с выбором растёт
    # на единицу. Считается ядром (`Rules.Spells`), LiveView только красит.
    test "выбор школы даёт +1 слот на каждый круг — видно в итогах", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      assert has_element?(view, "#spell-day-wizard [title='Круг 0: 3']")
      assert has_element?(view, "#spell-day-wizard [title='Круг 1: 1']")
      refute has_element?(view, "#spell-day-wizard-school")

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      # Круг 0 (заговоры) не растёт — источник не говорит явно, что бонус
      # его касается (см. `spellcasting.json` → `min_circle_note`), а круг 1
      # растёт на единицу.
      assert has_element?(view, "#spell-day-wizard [title='Круг 0: 3']")
      assert has_element?(view, "#spell-day-wizard [title='Круг 1: 2']")

      # Разбор «из чего собралось» (задача 3.6 применена и здесь): школа
      # названа рядом с числом, которое она объясняет.
      assert has_element?(view, "#spell-day-wizard-school", "Evocation")
    end

    # Задача 3.70: бонусные слоты за высокую характеристику каста. Числа
    # считает ядро (`Rules.Spells`), LiveView только печатает — и обязан
    # печатать ПОДПИСЬ: строка слотов выросла, а причина иначе нигде не
    # названа, и выросшее число читается как ошибка калькулятора.
    test "бонусные слоты за высокую характеристику видны и подписаны", %{
      conn: conn,
      ruleset: ruleset
    } do
      # Колдун 1-го уровня: строка таблицы {"0": 5, "1": 3}. Харизма 18 —
      # модификатор +4, значит один бонусный слот 1-го круга и ни одного
      # на заговорах.
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:sorcerer],
          base_abilities: %{str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 18},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert has_element?(view, "#spell-day-sorcerer [title='Круг 0: 5']")
      assert has_element?(view, "#spell-day-sorcerer [title='Круг 1: 4']")
      assert has_element?(view, "#spell-day-sorcerer-ability", "CHA +4: +1 слот")
    end

    # Обратный контроль к предыдущему: у той же строки с харизмой 10 подписи
    # нет вовсе — «+0 за CHA» объясняло бы пустоту, а не число.
    test "без бонуса подписи про характеристику нет", %{conn: conn, ruleset: ruleset} do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:sorcerer],
          base_abilities: %{str: 8, dex: 8, con: 8, int: 8, wis: 8, cha: 11},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert has_element?(view, "#spell-day-sorcerer [title='Круг 1: 3']")
      refute has_element?(view, "#spell-day-sorcerer-ability")
    end

    # 🔴 Задача 3.86: цена выбора названа ЧИСЛОМ и ТЕКСТОМ на самом чипе.
    # ⚠️ Здесь стоял тест «школа-антипод названа в подсказке кнопки»: имя
    # антипода лежало в `title`, то есть на мобильном не существовало вовсе,
    # и числа в нём не было — игрок видел у специализации одну выгоду.
    test "цена школы стоит на чипе: антипод и сколько заклинаний он закрывает", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      evocation = render(element(view, "#class-choice-evocation"))
      assert evocation =~ "Conjuration"

      # Число — не из этого теста: оно приходит из ядра и проверяется таблицей
      # в `SpellSchoolTest`. Здесь важно, что оно ДОЕХАЛО до экрана и стоит
      # рядом со своим знаменателем.
      costs = Spells.specialization_costs(Data.ruleset!(), :wizard)
      %{spells: spells, list_size: total} = costs.evocation

      assert evocation =~ "#{spells}"
      assert evocation =~ "#{total}"
      assert has_element?(view, "#class-choice-evocation-cost")

      # И вторая половина выбора — что он ДАЁТ — стоит над чипами, одной
      # строкой на все восемь школ. Обе половины на экране или ни одной:
      # порознь каждая делает выбор однобоким.
      assert has_element?(view, "#class-choice-gain", "к слотам каждого круга")
    end

    # Цена считается по СИАЛЬСКОЙ школе, а не по ванильной: шард унёс пять
    # «рук» Бигби из Разрушения в Зачарование, и специализация на Иллюзии
    # закрывает 20 заклинаний, а не 16. Ровно то число, которое ошиблось бы
    # молча, если бы школу читали из ванильного слоя.
    test "число на чипе — сиальское, а не ванильное", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      illusion = render(element(view, "#class-choice-illusion"))
      assert illusion =~ "Enchantment"
      assert illusion =~ "20"
      refute illusion =~ "16"
    end

    # Положительный контроль к обеим строкам выше: у клирика ни цены, ни
    # выгоды нет вовсе — его выбор арифметики за собой не несёт, и чип
    # выглядит ровно как до задачи 3.86.
    test "у доменов клирика цены на чипе нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      assert has_element?(view, "#class-choice-air")
      refute has_element?(view, "#class-choice-air-cost")
      refute has_element?(view, "#class-choice-gain")
    end

    # Положительный контроль на весь блок выше: без него зелёные тесты были
    # бы неотличимы от реализации, которая просто ничего не проверяет.
    test "у обычного заклинателя без записи специализации секции нет", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-sorcerer") |> render_click()

      refute has_element?(view, "#section-domains")
      refute has_element?(view, "#spell-day-sorcerer-school")
    end

    # Билд, открытый по ссылке с уже выбранной школой, приходит с верными
    # числами сразу — не только после клика в свежей сессии.
    test "билд со школой, открытый по ссылке, показывает +1 слот сразу", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          levels: [:wizard],
          # ⚠️ Интеллект назван, и с задачи 3.125 он обязателен: строку первого
          # круга видит только тот, кто этот круг кастует (нужно 10 + круг), а
          # умолчание `Build.new/1` — десятки во всех шести. Волшебника с
          # интеллектом 10 в игре и не создать — минимум ключевой
          # характеристики кастера выкупается принудительно (CLAUDE.md §6).
          # ⚠️ Именно 11, а не больше: 12 добавило бы ещё и БОНУСНЫЙ слот
          # за характеристику (задача 3.70), и «+1 за школу» перестало бы
          # быть тем, что проверяет этот тест.
          base_abilities: %{str: 10, dex: 10, con: 10, int: 11, wis: 10, cha: 10},
          class_choices: %{wizard: [:necromancy]},
          feats: %{1 => %{general: :toughness}}
        )

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}")

      assert has_element?(view, "#spell-day-wizard [title='Круг 1: 2']")
      assert has_element?(view, "#spell-day-wizard-school", "Necromancy")
    end
  end

  # Задача 3.170 (AGENT_QUEUE.md): в игре первым пунктом стоит `General` —
  # «без специализации», выбранный по умолчанию (скриншот Dan 02.09.2026).
  # У нас его не было — восемь школ и подпись «необязательно», а сказать
  # «я решил быть универсалистом» было нечем.
  describe "«без специализации» — кнопка General (задача 3.170)" do
    test "свежий волшебник: General уже выбран, слот пуст", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      assert has_element?(view, "#class-choice-none", "General")
      assert has_element?(view, "#class-choice-none[data-chosen='1']")

      # Ничего снимать не с чего — та же логика, что у школы без места
      # в чипах ниже (`value.disabled?`).
      assert has_element?(view, "#class-choice-none[disabled]")
    end

    test "выбор школы снимает General; клик по General возвращает универсала", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      refute has_element?(view, "#class-choice-none[data-chosen='1']")
      refute has_element?(view, "#class-choice-none[disabled]")
      assert has_element?(view, "#class-choice-evocation[data-chosen='1']")

      view |> element("#class-choice-none") |> render_click()

      assert has_element?(view, "#class-choice-none[data-chosen='1']")
      assert has_element?(view, "#class-choice-none[disabled]")
      refute has_element?(view, "#class-choice-evocation[data-chosen='1']")

      %{socket: %{assigns: %{build: build}}} = :sys.get_state(view.pid)
      assert Build.class_choice(build, :wizard) == []
    end

    # Положительный контроль: без него оба теста выше были бы неотличимы
    # от реализации, которая рисует кнопку всем классам подряд. Клирика
    # выбор ОБЯЗАТЕЛЕН — «без домена» незаконное состояние, и кнопки
    # у него нет ни при каких условиях.
    test "у клирика кнопки General нет вовсе", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      assert has_element?(view, "#class-choice-air")
      refute has_element?(view, "#class-choice-none")
    end
  end

  # Задача 3.171, замечание 1 Dan: «Когда она выбрана в лестнице слева на
  # 1 уровне виза отображается "выбрать школу магии", можно было бы
  # отображать, что выбрано general». Панель итогов уже печатала «General»
  # (задача 3.170, `Summary.guide_domains/3`) — лестница молчала о том же
  # самом билде.
  describe "лестница называет General — задача 3.171, замечание 1" do
    test "свежий волшебник: лестница печатает General, а не «выбрать школу магии»", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      domains_text = render(element(view, "#level-1-domains"))
      assert domains_text =~ "General"
      refute domains_text =~ "выбрать школу магии"
    end

    test "после выбора школы лестница называет школу, а не General", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      domains_text = render(element(view, "#level-1-domains"))
      assert domains_text =~ "Evocation"
      refute domains_text =~ "General"
    end

    # Отрицательный контроль: у Клирика (обязательный выбор, слова для
    # «ничего» нет — `no_selection_name` в данных не заполняется) лестница
    # не меняется этой правкой.
    test "у клирика лестница по-прежнему зовёт «выбрать домены»", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()

      domains_text = render(element(view, "#level-1-domains"))
      assert domains_text =~ "выбрать домены"
    end
  end

  # Задача 3.171, замечание 2 Dan: «в других местах сайта у нас можно свободно
  # переключаться между различными выборами чего-либо. Логичнее было бы не
  # блокировать другие школы, просто выделить ту что выбрали. С возможностью
  # выбрать другую» — прецедент прямо в этом же файле, `pick_increase`
  # (выбор одной характеристики из шести): клик по другой заменяет,
  # заблокированных кнопок нет вовсе.
  describe "клик по школе меняет выбор — задача 3.171, замечание 2" do
    @schools ~w(abjuration conjuration divination enchantment evocation illusion necromancy transmutation)

    test "ни одна школа не disabled ни в каком состоянии волшебника", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      for school <- @schools do
        refute has_element?(view, "#class-choice-#{school}[disabled]")
      end

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      for school <- @schools do
        refute has_element?(view, "#class-choice-#{school}[disabled]")
      end
    end

    test "клик по другой школе меняет выбор ОДНИМ кликом", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      assert has_element?(view, "#class-choice-evocation[data-chosen='1']")
      refute has_element?(view, "#class-choice-abjuration[data-chosen='1']")

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "abjuration"})

      refute has_element?(view, "#class-choice-evocation[data-chosen='1']")
      assert has_element?(view, "#class-choice-abjuration[data-chosen='1']")

      %{socket: %{assigns: %{build: build}}} = :sys.get_state(view.pid)
      assert Build.class_choice(build, :wizard) == [:abjuration]
    end

    # Числа не должны сдвинуться при смене школы: слот остаётся
    # «со специализацией» (+1 на круг), просто у ДРУГОЙ школы — замена,
    # а не потеря выбора по дороге.
    test "числа слотов остаются такими же после смены школы", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      assert has_element?(view, "#spell-day-wizard [title='Круг 1: 2']")

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "abjuration"})

      assert has_element?(view, "#spell-day-wizard [title='Круг 1: 2']")
      assert has_element?(view, "#spell-day-wizard-school", "Abjuration")
    end

    # Отрицательный контроль: у Клирика (`count: 2`) блокировка остаётся —
    # какой из двух вытеснять новым кликом, правила нет ни у источника, ни
    # у здравого смысла (`ClassChoices.click/4`). Тот же сценарий уже
    # проверен выше, в блоке про домены клирика («третий домен не
    # добавляется сверх count»); здесь — прямая привязка к приёмке 3.171.
    test "у клирика при двух выбранных доменах остальные по-прежнему disabled", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-cleric") |> render_click()
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "air"})
      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "war"})

      assert has_element?(view, "#class-choice-fire[disabled]")

      render_click(view, "toggle_class_choice", %{"class" => "cleric", "choice" => "fire"})

      refute has_element?(view, "#class-choice-fire[data-chosen='1']")
      assert has_element?(view, "#class-choice-air[data-chosen='1']")
      assert has_element?(view, "#class-choice-war[data-chosen='1']")
    end

    # Инвариант постановки 3.171: школа волшебника — необязательный выбор
    # (`required?: false`), `row_todo/2` не считает его вовсе (задача 3.9) —
    # ни свежий, ни выбранный, ни СМЕНЁННЫЙ клик не имеет права сдвинуть
    # счётчик «N не выбрано». Сравнение всей HTML-строки кнопки, а не только
    # числа в ней, — `phx-click`/`disabled` у неё завязаны на то же значение
    # и обязаны остаться такими же.
    test "счётчик «N не выбрано» не двигается от выбора и смены школы", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#level-1") |> render_click()
      view |> element("#class-card-wizard") |> render_click()

      before_school = render(element(view, "#spine-todo"))
      assert before_school =~ ~r/\d+ не выбрано/

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "evocation"})

      after_pick = render(element(view, "#spine-todo"))
      assert after_pick == before_school

      view
      |> render_click("toggle_class_choice", %{"class" => "wizard", "choice" => "abjuration"})

      after_replace = render(element(view, "#spine-todo"))
      assert after_replace == before_school
    end
  end

  # ⚠️ Блок назывался «выбор для ВЫДАННОГО фита — Weapon of choice (задача 3.26)»
  # и проверял чипы `#granted-choice-*` плюс событие `toggle_granted_choice`.
  # Замеры M2/M2b (14.08.2026) показали, что класс этот фит не выдаёт вовсе:
  # первый уровень Мастера оружия даёт СЛОТ, и `Weapon of choice` берётся в него
  # наравне с пятью сиальскими владениями. Значит и выбор оружия делается
  # обычным вторым шагом пика — тем же `#feat-choice-*`, что у `Spell focus`.
  #
  # 🔴 У механизма «выданный фит с выбором» (`granted_choices`, чипы,
  # `toggle_granted_choice`, глиф `◆` в лестнице) НЕ ОСТАЛОСЬ НИ ОДНОГО
  # НОСИТЕЛЯ В ДАННЫХ — проверено обходом `granted_feats` всех 23 классов.
  # Код и форма живы, решение об их судьбе за Dan (GAME_CHECKS.md, M2b).
  # Здесь проверяется то, что видит игрок СЕГОДНЯ: тот же выбор, другой путь.
  describe "Weapon of choice берётся слотом, и оружие выбирается вторым шагом" do
    defp wm_link(ruleset, opts \\ []) do
      Build.new(
        [
          ruleset_version: ruleset.version,
          race: :human,
          alignment: :lawful_good,
          levels: List.duplicate(:fighter, 13) ++ List.duplicate(:weapon_master, 28),
          base_abilities: %{str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 8},
          feats: %{
            1 => %{
              {:class_bonus, :fighter} => :siala_blade_proficiency,
              :general => {:weapon_focus, :scimitar}
            },
            3 => %{general: {:weapon_focus, :longsword}}
          }
        ] ++ opts
      )
    end

    test "на 14-м есть классовый слот и в нём предлагается Weapon of choice", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(wm_link(ruleset))}")

      view |> element("#level-14") |> render_click()
      assert has_element?(view, "#slot-chip-class_bonus-weapon_master")
      assert has_element?(view, "#feat-ok-weapon_of_choice")

      # ⚠️ Отрицательный контроль в том же тесте: на 15-м классового слота нет,
      # и фит там не предлагается. Порознь первая половина зеленела бы
      # и у разметки, которая печатает слот на каждом уровне.
      view |> element("#level-15") |> render_click()
      refute has_element?(view, "#slot-chip-class_bonus-weapon_master")
    end

    test "клик открывает выбор оружия, и в нём только оружие с фокусом", %{
      conn: conn,
      ruleset: ruleset
    } do
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(wm_link(ruleset))}")

      view |> element("#level-14") |> render_click()
      view |> element("#feat-ok-weapon_of_choice") |> render_click()

      assert has_element?(view, "#feat-choice-scimitar")
      assert has_element?(view, "#feat-choice-longsword")

      # Рапира — оружие домена, но фокуса на неё нет: ядро её не предлагает.
      refute has_element?(view, "#feat-choice-rapier")
    end

    # 🔴 Живое число задачи 3.26: у билда с ДВУМЯ фокусами колонка «AB bonus»
    # Мастера оружия (+7) не считается, пока оружие не названо, — фокусов два,
    # и вывести его не из чего. Выбор её возвращает.
    test "выбранное оружие возвращает колонку ВМ в разбор AB", %{conn: conn, ruleset: ruleset} do
      link = wm_link(ruleset, gear: Gear.new(weapon: :scimitar))
      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(link)}")

      view |> element("#level-14") |> render_click()

      before_terms = pop_terms(render(element(view, "#stat-attack_bonus")), "stat-attack_bonus")

      view |> element("#feat-ok-weapon_of_choice") |> render_click()
      view |> element("#feat-choice-scimitar") |> render_click()

      after_terms = pop_terms(render(element(view, "#stat-attack_bonus")), "stat-attack_bonus")

      assert sum_terms(after_terms) - sum_terms(before_terms) == 7
    end

    # Складывает термы разбора AB: у поп-апа они строками со знаком.
    defp sum_terms(terms) do
      for %{"value" => value} <- terms, reduce: 0 do
        acc ->
          case Integer.parse(String.trim_leading(value, "+")) do
            {number, _rest} -> acc + number
            :error -> acc
          end
      end
    end
  end

  # 🔴 БЛОК СНЯТ 14.08.2026, И ЭТО ПРОДУКТОВОЕ ПОСЛЕДСТВИЕ, А НЕ УБОРКА ТЕСТОВ.
  #
  # Он проверял наблюдение Dan от 10.08.2026: «это как бы бесплатный
  # автоматический фит, но там есть выбор оружия, было бы здорово его видеть»,
  # — отсюда строка `#level-N-granted-<feat>` в лестнице с глифом `◆`, янтарь
  # «не выбрано» и счётчик незакрытых решений в шапке.
  #
  # Замеры M2/M2b показали, что фит НЕ бесплатный и НЕ автоматический: первый
  # уровень Мастера оружия даёт слот. А слоты лестница печатает и так, вместе
  # с выбранным значением, — то есть то, что Dan просил видеть, он видит,
  # просто обычной строкой пика. Носителей у механизма выдачи-с-выбором
  # не осталось ни одного (обход `granted_feats` всех 23 классов).
  #
  # ⚠️ Код механизма НЕ удалён: `granted_choices` в билде, чипы, событие
  # `toggle_granted_choice` и разметка строки живы, и решение об их судьбе
  # за Dan. Пока у них нет носителя, тесты на них зеленели бы впустую —
  # поэтому здесь их нет, а сам механизм остаётся под тестом ядра
  # (`BuildTest`, синтетический ruleset без подстановки).

  describe "список недоступных фитов отдаётся целиком, без потолка (задача 3.115)" do
    # Тот же билд, что закреплён юнит-тестом `Builder.FeatsTest` («список
    # недоступных без потолка») — воин 21-го уровня, `blocked_total` 75,
    # то есть больше прежнего `@blocked_limit` (50). До правки в DOM было бы
    # только 50 + owned-хвост строк и живая `#feats-blocked-more`.
    test "DOM несёт все недоступные строки, а не первые 50, и «…и ещё N» пропала", %{
      conn: conn,
      ruleset: ruleset
    } do
      build =
        Build.new(
          ruleset_version: ruleset.version,
          race: :human,
          levels: List.duplicate(:fighter, 21)
        )

      truth = Feats.lists(ruleset, build, 21, query: "", type: "all", slot: nil)

      assert truth.blocked_total > 50

      {:ok, view, _html} = live(conn, ~p"/?b=#{Encoding.encode(build)}&l=21")
      doc = view |> render() |> LazyHTML.from_fragment()

      rendered_blocked_ids =
        doc |> LazyHTML.query("[id^='feat-no-']") |> LazyHTML.attribute("id") |> MapSet.new()

      truth_blocked_ids = MapSet.new(truth.blocked, &"feat-no-#{&1.feat.id}")

      # Положительный контроль внутри самой проверки: `MapSet` sizes сходятся
      # только если ничего не обрезано — сравнение множеств, а не счётчик,
      # тем же приёмом, что и «холодный старт» выше (задача 3.66).
      assert rendered_blocked_ids == truth_blocked_ids
      assert MapSet.size(rendered_blocked_ids) == truth.blocked_total

      count_text = doc |> LazyHTML.query("#feats-blocked-count") |> LazyHTML.text()
      assert count_text == "Недоступные · #{truth.blocked_total}"

      refute has_element?(view, "#feats-blocked-more")
    end
  end
end
