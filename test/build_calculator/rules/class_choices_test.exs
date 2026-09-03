defmodule BuildCalculator.Rules.ClassChoicesTest do
  @moduledoc """
  A class's own one-time choice, held for the rest of the build.

  Fictional class and domain ids throughout the mechanism tests (`@class`,
  `@domain`), the same way `FeatChoicesTest` uses `:fixture_repeatable` —
  `class_choices.json` is real game data, subject to change, and a test
  pinned to `:cleric` would measure that data rather than the rule
  (CLAUDE.md §3). The one exception is the "real data" describe block at the
  bottom, which exists precisely to catch the day the data stops matching
  what the mechanism assumes.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules.{Build, ClassChoices}

  @class :fixture_class
  @domain :fixture_domain
  @values MapSet.new([:alpha, :beta, :gamma])

  defp ruleset(class_choices, values \\ @values) do
    %{
      class_choices: class_choices,
      choice_domains: %{@domain => %{values: values, flags: %{}, names: %{}, source: :file}}
    }
  end

  defp required_ruleset(count \\ 2) do
    ruleset(%{@class => %{domain: @domain, count: count, distinct?: true, required?: true}})
  end

  defp optional_ruleset(count \\ 1) do
    ruleset(%{@class => %{domain: @domain, count: count, distinct?: true, required?: false}})
  end

  describe "spec/2, domain/2, required?/2" do
    test "a class with no entry has no choice at all" do
      ruleset = ruleset(%{})

      assert ClassChoices.spec(@class, ruleset) == nil
      assert ClassChoices.domain(@class, ruleset) == nil
      refute ClassChoices.required?(@class, ruleset)
    end

    test "a class with an entry answers all three from it" do
      ruleset = required_ruleset()

      assert %{domain: @domain, count: 2} = ClassChoices.spec(@class, ruleset)
      assert ClassChoices.domain(@class, ruleset) == @domain
      assert ClassChoices.required?(@class, ruleset)
    end

    test "an optional choice is not required?" do
      refute ClassChoices.required?(@class, optional_ruleset())
    end
  end

  # Задача 3.170: слово клиента для «ничего не выбрано» — Волшебника
  # `General`. Синтетический ruleset здесь, не реальный: у самих
  # `required_ruleset/1` и `optional_ruleset/1` выше `no_selection_name` не
  # заполнен вовсе — ровно тот hand-built ruleset без ключа, ради которого
  # `no_selection_name/2` читает через `Map.get/2`, а не точечным доступом.
  describe "no_selection_name/2" do
    test "a class with no choice mechanic has no word for it" do
      assert ClassChoices.no_selection_name(@class, ruleset(%{})) == nil
    end

    test "a hand-built spec that never named the key answers nil, not KeyError" do
      assert ClassChoices.no_selection_name(@class, required_ruleset()) == nil
      assert ClassChoices.no_selection_name(@class, optional_ruleset()) == nil
    end

    test "a spec that does name it answers the word" do
      ruleset =
        ruleset(%{
          @class => %{
            domain: @domain,
            count: 1,
            distinct?: true,
            required?: false,
            no_selection_name: "General"
          }
        })

      assert ClassChoices.no_selection_name(@class, ruleset) == "General"
    end
  end

  describe "values/2" do
    test "a class with no choice mechanic answers :no_choice" do
      assert ClassChoices.values(@class, ruleset(%{})) == :no_choice
    end

    test "a class with a resolved domain gets its values, sorted" do
      assert ClassChoices.values(@class, required_ruleset()) == {:ok, [:alpha, :beta, :gamma]}
    end

    test "a class whose domain has no dictionary answers :none, not :no_choice" do
      # `values: nil` is `Loader.Reading.resolve_domain/3`'s "known to the data, no
      # dictionary" answer — see `BuildCalculator.Data.Loader`.
      ruleset = %{
        class_choices: %{@class => %{domain: @domain, count: 2, required?: true}},
        choice_domains: %{@domain => %{values: nil, flags: %{}, names: %{}, source: nil}}
      }

      assert ClassChoices.values(@class, ruleset) == :none
    end
  end

  describe "complete?/3" do
    test "a class with no choice mechanic is trivially complete" do
      build = Build.new(levels: [@class])
      refute ClassChoices.spec(@class, ruleset(%{}))
      assert ClassChoices.complete?(build, @class, ruleset(%{}))
    end

    test "an optional choice is complete with zero values held" do
      build = Build.new(levels: [@class])
      assert ClassChoices.complete?(build, @class, optional_ruleset())
    end

    test "a required choice is incomplete until it holds `count` values" do
      ruleset = required_ruleset(2)
      empty = Build.new(levels: [@class])
      one = Build.toggle_class_choice(empty, @class, :alpha)
      two = Build.toggle_class_choice(one, @class, :beta)

      refute ClassChoices.complete?(empty, @class, ruleset)
      refute ClassChoices.complete?(one, @class, ruleset)
      assert ClassChoices.complete?(two, @class, ruleset)
    end
  end

  describe "reasons/4 and validate/4" do
    test "a class with no choice mechanic refuses with :no_choice" do
      build = Build.new(levels: [@class])
      assert ClassChoices.reasons(build, @class, :alpha, ruleset(%{})) == [{:no_choice, @class}]

      assert {:error, [{:no_choice, @class}]} =
               ClassChoices.validate(build, @class, :alpha, ruleset(%{}))
    end

    test "an unresolved domain refuses with the same gap a feat's choice would" do
      ruleset = %{
        class_choices: %{@class => %{domain: @domain, count: 2, required?: true}},
        choice_domains: %{@domain => %{values: nil, flags: %{}, names: %{}, source: nil}}
      }

      build = Build.new(levels: [@class])

      assert ClassChoices.reasons(build, @class, :alpha, ruleset) == [
               {:missing_data, {:choice_domain, @domain}}
             ]
    end

    test "a value outside the domain is refused" do
      build = Build.new(levels: [@class])

      assert ClassChoices.validate(build, @class, :not_a_value, required_ruleset()) ==
               {:error, [{:invalid_class_choice, @class, :not_a_value}]}
    end

    test "a legal value with room left is :ok" do
      build = Build.new(levels: [@class])
      assert ClassChoices.validate(build, @class, :alpha, required_ruleset()) == :ok
    end

    test "a value already held is :ok — asking to add it again is not a duplicate error" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)
      assert ClassChoices.validate(build, @class, :alpha, required_ruleset()) == :ok
    end

    test "a fresh value is refused once `count` is already held" do
      ruleset = required_ruleset(2)

      build =
        Build.new(levels: [@class])
        |> Build.toggle_class_choice(@class, :alpha)
        |> Build.toggle_class_choice(@class, :beta)

      assert ClassChoices.validate(build, @class, :gamma, ruleset) ==
               {:error, [{:class_choice_full, @class, 2}]}
    end

    test "taking a value back is never asked about here — that is Build.toggle_class_choice/3's job" do
      # `reasons/4` only answers "may I ADD this" (see moduledoc); removing is
      # not modelled as a refusable action at all.
      build =
        Build.new(levels: [@class])
        |> Build.toggle_class_choice(@class, :alpha)
        |> Build.toggle_class_choice(@class, :beta)

      after_removal = Build.toggle_class_choice(build, @class, :alpha)
      assert Build.class_choice(after_removal, @class) == [:beta]
    end

    # Задача 3.171: `reasons/4`'s own contract does NOT change — it still
    # answers "may this be appended outright", and a `count == 1` choice
    # already holding a value has no room for a second one appended. What
    # changes is who reads that answer: `click/4` below turns exactly this
    # shape into `:replace` instead of a refusal. If this test regressed to
    # `:ok`, `click/4`'s `[{:class_choice_full, ^class_id, 1}]` clause would
    # stop matching anything, and every Wizard school swap would silently
    # start APPENDING instead of replacing.
    test "a fresh value is refused once `count: 1` already holds one — reasons/4 itself is unchanged" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)

      assert ClassChoices.validate(build, @class, :beta, optional_ruleset(1)) ==
               {:error, [{:class_choice_full, @class, 1}]}
    end
  end

  # Задача 3.171: у клика на чип есть три исхода — `:toggle` (снять
  # взятое или добавить в свободный слот), `:replace` (выбор из ОДНОГО
  # значения полон, клик меняет выбор) и отказ (`reasons/4`, без изменений).
  # `Rules.ClassChoices.click/4` — единственное место, где решается, какой
  # из трёх это.
  describe "click/4" do
    test "a value already held is :toggle, regardless of count" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)

      assert ClassChoices.click(build, @class, :alpha, required_ruleset(2)) == :toggle
      assert ClassChoices.click(build, @class, :alpha, optional_ruleset(1)) == :toggle
    end

    test "a fresh value with room left is :toggle" do
      build = Build.new(levels: [@class])
      assert ClassChoices.click(build, @class, :alpha, required_ruleset(2)) == :toggle
    end

    test "a fresh value on a FULL count: 1 choice is :replace" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)
      assert ClassChoices.click(build, @class, :beta, optional_ruleset(1)) == :replace
    end

    test "a fresh value on a FULL count: 2 choice stays refused — no rule says which to evict" do
      build =
        Build.new(levels: [@class])
        |> Build.toggle_class_choice(@class, :alpha)
        |> Build.toggle_class_choice(@class, :beta)

      assert ClassChoices.click(build, @class, :gamma, required_ruleset(2)) ==
               {:error, [{:class_choice_full, @class, 2}]}
    end

    test "an out-of-domain value is refused even on a full count: 1 choice — never :replace" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)

      # `reasons/4` names BOTH problems here (wrong domain, no room either) —
      # `click/4` only reads `:replace` off the single, EXACT
      # `[{:class_choice_full, class_id, 1}]` shape, so two reasons together
      # fall straight through to the generic refusal, same as `reasons/4`
      # itself would answer.
      assert ClassChoices.click(build, @class, :not_a_value, optional_ruleset(1)) ==
               {:error,
                [
                  {:invalid_class_choice, @class, :not_a_value},
                  {:class_choice_full, @class, 1}
                ]}
    end

    test "a class with no choice mechanic refuses, same as reasons/4" do
      build = Build.new(levels: [@class])

      assert ClassChoices.click(build, @class, :alpha, ruleset(%{})) ==
               {:error, [{:no_choice, @class}]}
    end
  end

  describe "Build.class_choice/2 and Build.toggle_class_choice/3" do
    test "an untouched class has no choice recorded" do
      build = Build.new(levels: [@class])
      assert Build.class_choice(build, @class) == []
    end

    test "toggling adds, toggling the same value again removes" do
      build = Build.new(levels: [@class])
      build = Build.toggle_class_choice(build, @class, :alpha)
      assert Build.class_choice(build, @class) == [:alpha]

      build = Build.toggle_class_choice(build, @class, :alpha)
      assert Build.class_choice(build, @class) == []
    end

    test "a build with no choices for a class round trips through class_choices as %{}" do
      build = Build.new(levels: [@class])
      assert build.class_choices == %{}
    end
  end

  # Задача 3.171: единственный вызывающий сегодня — `click/4`, только для
  # `:replace`, только у `count == 1`. Тест здесь берёт функцию буквально,
  # как и её собственная документация («unconditionally») — она сама не
  # смотрит на count вовсе, это забота вызывающего.
  describe "Build.replace_class_choice/3" do
    test "an untouched class ends up holding exactly the one value" do
      build = Build.new(levels: [@class])
      replaced = Build.replace_class_choice(build, @class, :alpha)
      assert Build.class_choice(replaced, @class) == [:alpha]
    end

    test "a class already holding a DIFFERENT value loses it — replace, not append" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)
      replaced = Build.replace_class_choice(build, @class, :beta)
      assert Build.class_choice(replaced, @class) == [:beta]
    end

    test "replacing with the value already held is a no-op" do
      build = Build.new(levels: [@class]) |> Build.toggle_class_choice(@class, :alpha)
      replaced = Build.replace_class_choice(build, @class, :alpha)
      assert Build.class_choice(replaced, @class) == [:alpha]
    end

    test "literal to its own doc — MULTIPLE held values are also collapsed to the one" do
      build =
        Build.new(levels: [@class])
        |> Build.toggle_class_choice(@class, :alpha)
        |> Build.toggle_class_choice(@class, :beta)

      replaced = Build.replace_class_choice(build, @class, :gamma)
      assert Build.class_choice(replaced, @class) == [:gamma]
    end
  end

  describe "pruning — a choice does not outlive its class" do
    test "truncating past a class's only level drops its choice" do
      build =
        Build.new(levels: [@class, @class])
        |> Build.toggle_class_choice(@class, :alpha)
        |> Build.toggle_class_choice(@class, :beta)

      assert Build.class_choice(build, @class) == [:alpha, :beta]

      truncated = Build.truncate(build, 0)
      assert Build.class_choice(truncated, @class) == []
      assert truncated.class_choices == %{}
    end

    test "truncating to a level that still has the class keeps the choice" do
      build =
        Build.new(levels: [@class, :other, @class])
        |> Build.toggle_class_choice(@class, :alpha)

      # Cuts off the SECOND @class level, but the first one is still there.
      truncated = Build.truncate(build, 2)
      assert Build.class_choice(truncated, @class) == [:alpha]
    end

    test "replacing the only level of a class with something else drops its choice" do
      build =
        Build.new(levels: [@class])
        |> Build.toggle_class_choice(@class, :alpha)

      replaced = Build.replace_level(build, 1, :other)
      assert Build.class_choice(replaced, @class) == []
      assert replaced.class_choices == %{}
    end

    test "replacing a DIFFERENT level leaves an existing class's choice alone" do
      build =
        Build.new(levels: [@class, :other])
        |> Build.toggle_class_choice(@class, :alpha)

      replaced = Build.replace_level(build, 2, :other)
      assert Build.class_choice(replaced, @class) == [:alpha]
    end
  end

  # ------------------------------------------------------------- real data --

  describe "the real siala_41 ruleset" do
    setup do
      %{ruleset: Data.ruleset!("siala_41")}
    end

    # Проверка предпосылки задачи 3.14, а не просто регрессия: AGENT_QUEUE.md
    # утверждал «19 доменов», и это число обязано быть проверено кодом, а не
    # только руками при заведении данных.
    test "cleric asks for exactly two, distinct, required domains", %{ruleset: ruleset} do
      assert ClassChoices.spec(:cleric, ruleset) == %{
               domain: :domain,
               count: 2,
               distinct?: true,
               required?: true,
               # Задача 3.170: обязательный выбор не имеет права на слово
               # «ничего не выбрано» — «без домена» незаконное состояние.
               no_selection_name: nil
             }
    end

    test "there are exactly nineteen domains to choose from", %{ruleset: ruleset} do
      assert {:ok, values} = ClassChoices.values(:cleric, ruleset)
      assert length(values) == 19

      assert values == [
               :air,
               :animal,
               :death,
               :destruction,
               :earth,
               :evil,
               :fire,
               :good,
               :healing,
               :knowledge,
               :magic,
               :plant,
               :protection,
               :strength,
               :sun,
               :travel,
               :trickery,
               :war,
               :water
             ]
    end

    # 🔴 Задача 3.79 (22.08.2026): `{:not_modelled, :cleric_domains}` снят
    # из `ruleset.gaps` решением Dan — «домены клерика дают ему новые
    # заклинания, но выбирать их не надо, они выдаются автоматически.
    # Получается для конструктора здесь делать нечего». Ушло ПРИЗНАНИЕ,
    # а не механика, и этот тест — единственное место, где разницу видно
    # обеими половинами сразу: гэпа в списке нет, а выбор двух доменов
    # по-прежнему обязателен и по-прежнему держит уровень незакрытым.
    #
    # ⚠️ Без второй половины «уберём домены» однажды прочтут шире, чем сказано:
    # соседний тест `spec/2` проверяет только форму записи в данных и зеленел
    # бы и у ruleset'а, чей `complete?/3` разучился ждать выбор.
    # ⚠️ Проверяется на НАСТОЯЩЕМ ruleset'е сознательно, вопреки правилу
    # moduledoc про фиктивные id: утверждение здесь именно про `:cleric`
    # и про то, что правка 3.79 его не задела.
    test "гэп снят, а выбор двух доменов остался обязательным", %{ruleset: ruleset} do
      refute {:not_modelled, :cleric_domains} in ruleset.gaps

      build = Build.new(levels: [:cleric], ruleset_version: ruleset.version)

      refute ClassChoices.complete?(build, :cleric, ruleset),
             "клирик 1-го уровня без выбранных доменов — уровень не закрыт"

      one = Build.toggle_class_choice(build, :cleric, :air)

      refute ClassChoices.complete?(one, :cleric, ruleset),
             "одного домена из двух мало — уровень всё ещё не закрыт"

      two = Build.toggle_class_choice(one, :cleric, :war)

      assert ClassChoices.complete?(two, :cleric, ruleset)
      assert Build.class_choice(two, :cleric) == [:air, :war]

      # И выбор остаётся выбором: значение вне домена по-прежнему отбивается,
      # а третий домен упирается в `count`. Снятый гэп не открыл ни одну
      # из двух дверей.
      assert ClassChoices.validate(build, :cleric, :not_a_domain, ruleset) ==
               {:error, [{:invalid_class_choice, :cleric, :not_a_domain}]}

      assert ClassChoices.validate(two, :cleric, :fire, ruleset) ==
               {:error, [{:class_choice_full, :cleric, 2}]}
    end

    # Положительный контроль: без него зелёный тест выше был бы неотличим от
    # реализации, которая молча даёт выбор всем классам подряд.
    test "an ordinary class has no choice at all", %{ruleset: ruleset} do
      assert ClassChoices.spec(:fighter, ruleset) == nil
      assert ClassChoices.values(:fighter, ruleset) == :no_choice
      assert ClassChoices.complete?(Build.new(levels: [:fighter]), :fighter, ruleset)
    end

    test "vanilla carries the same choice — Siala renamed nothing about domains" do
      ruleset = Data.ruleset!("vanilla")

      assert ClassChoices.spec(:cleric, ruleset) == %{
               domain: :domain,
               count: 2,
               distinct?: true,
               required?: true,
               # Задача 3.170: обязательный выбор не имеет права на слово
               # «ничего не выбрано» — «без домена» незаконное состояние.
               no_selection_name: nil
             }

      assert {:ok, values} = ClassChoices.values(:cleric, ruleset)
      assert length(values) == 19
    end

    # Задача 3.10. `required?: false` — прямое следствие «A wizard does not
    # have to specialize, thus keeping access to all spells» (Fandom
    # «Wizard»). Это единственное отличие от клирика в этом тесте: домен,
    # число значений и `distinct?` устроены одной и той же машинерией.
    test "wizard asks for exactly one, distinct, OPTIONAL school", %{ruleset: ruleset} do
      assert ClassChoices.spec(:wizard, ruleset) == %{
               domain: :spell_school,
               count: 1,
               distinct?: true,
               required?: false,
               # Задача 3.170: слово, которым сам клиент называет «ничего
               # не выбрано» — печать игры (скриншот Dan), не Fandom's
               # `Universal` (то имя записи `spell_schools.json`, не пункта
               # меню).
               no_selection_name: "General"
             }
    end

    # Восемь школ, не девять: `universal` физически есть в словаре
    # `spell_schools.json` (у него есть страница на вики), но помечен
    # `selectable: false` — «не выбирается» кладётся отсутствием значения
    # в `class_choices`, а не отдельным пунктом списка. Ту же цитату уже
    # проверяет `Spell focus`, здесь — что `ClassChoices` читает тот же гейт
    # (найдено И ПОЧИНЕНО этой задачей: `ClassChoices.values/2` раньше гейт
    # не читал вовсе — у клирика это было незаметно, потому что `domains.json`
    # не несёт ни одного гейта).
    test "there are exactly eight schools to choose from — universal is excluded", %{
      ruleset: ruleset
    } do
      assert {:ok, values} = ClassChoices.values(:wizard, ruleset)
      assert length(values) == 8
      refute :universal in values

      assert values == [
               :abjuration,
               :conjuration,
               :divination,
               :enchantment,
               :evocation,
               :illusion,
               :necromancy,
               :transmutation
             ]
    end

    # `values/2` предлагает восемь — но что случится, если `universal` всё
    # равно попадёт в билд (старая ссылка, ручной POST)? Отказ, а не тихое
    # принятие: гейт применяется и на вход, не только на список.
    test "universal is refused even though it is a real value in the domain's file", %{
      ruleset: ruleset
    } do
      build = Build.new(levels: [:wizard])

      assert ClassChoices.validate(build, :wizard, :universal, ruleset) ==
               {:error, [{:invalid_class_choice, :wizard, :universal}]}
    end

    # Необязательный выбор без единого значения — легальный и завершённый
    # билд. Это главное отличие от клирика (`complete?/3` для required?:
    # true остаётся `false`, пока не набраны все `count`).
    test "an unmade optional choice is complete — a build without it is legal", %{
      ruleset: ruleset
    } do
      build = Build.new(levels: [:wizard])

      assert ClassChoices.complete?(build, :wizard, ruleset)
      assert Build.class_choice(build, :wizard) == []
    end

    # Задача 3.171, замечание 2 Dan: клик по другой школе МЕНЯЕТ выбор
    # одним кликом, а не блокируется. На настоящем ruleset'е, а не на
    # фикстуре — именно этот случай был замерен на проде.
    test "clicking a fresh school on a Wizard who already specialized REPLACES it", %{
      ruleset: ruleset
    } do
      build =
        Build.new(levels: [:wizard]) |> Build.toggle_class_choice(:wizard, :evocation)

      assert ClassChoices.click(build, :wizard, :abjuration, ruleset) == :replace

      replaced = Build.replace_class_choice(build, :wizard, :abjuration)
      assert Build.class_choice(replaced, :wizard) == [:abjuration]
    end

    # Отрицательный контроль того же замечания: у Клирика (`count: 2`)
    # заполненный выбор остаётся стеной — угадывать, какой из двух доменов
    # вытеснять, не должен ни калькулятор, ни игрок.
    test "a Cleric's full two domains stay refused — no :replace for count > 1", %{
      ruleset: ruleset
    } do
      build =
        Build.new(levels: [:cleric])
        |> Build.toggle_class_choice(:cleric, :fire)
        |> Build.toggle_class_choice(:cleric, :water)

      assert ClassChoices.click(build, :cleric, :war, ruleset) ==
               {:error, [{:class_choice_full, :cleric, 2}]}
    end

    test "vanilla carries the same wizard choice — Siala's page never mentions schools" do
      ruleset = Data.ruleset!("vanilla")

      assert ClassChoices.spec(:wizard, ruleset) == %{
               domain: :spell_school,
               count: 1,
               distinct?: true,
               required?: false,
               # Задача 3.170: слово, которым сам клиент называет «ничего
               # не выбрано» — печать игры (скриншот Dan), не Fandom's
               # `Universal` (то имя записи `spell_schools.json`, не пункта
               # меню).
               no_selection_name: "General"
             }

      assert {:ok, values} = ClassChoices.values(:wizard, ruleset)
      assert length(values) == 8
    end
  end
end
