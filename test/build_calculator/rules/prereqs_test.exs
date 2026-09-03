defmodule BuildCalculator.Rules.PrereqsTest do
  @moduledoc """
  The shared requirement interpreter, exercised through a feat.

  Feat records are built here by hand rather than taken out of
  `priv/rules/vanilla/feats.json`: the parser that fills that file is being
  extended right now, and a test pinned to one of its entries would be measuring
  somebody else's work in progress. Class **spell tables** are real, because
  `casts_spell_level` is only meaningful against them.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatChoices, Gear, Prereqs, Spells}

  @feat :fixture_feat

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  # A feat record with only the fields the prerequisite path reads. `prereqs`
  # carries string keys on purpose: that is the shape `mix wiki.parse` writes and
  # the loader hands over untouched.
  defp with_prereqs(ruleset, prereqs, opts \\ []) do
    feat = %{
      id: @feat,
      name: "Fixture feat",
      type: "general",
      epic?: false,
      bonus_for: MapSet.new(),
      available_to: MapSet.new(),
      prereq_raw: Keyword.get(opts, :prereq_raw),
      prereqs: prereqs,
      unlocks: [],
      repeatable: Keyword.get(opts, :repeatable),
      source: nil
    }

    put_in(ruleset.feats[@feat], feat)
  end

  # `choice:` asks about the feat taken **with** a value. Absent — every caller
  # that does not deal in choices — is the plain form, and must stay identical.
  defp check(ruleset, prereqs, build, opts \\ []) do
    ruleset = with_prereqs(ruleset, prereqs, opts)

    case Keyword.fetch(opts, :choice) do
      {:ok, choice} -> Rules.validate_feat(build, %{feat: @feat, choice: choice}, ruleset)
      :error -> Rules.validate_feat(build, @feat, ruleset)
    end
  end

  # ⚠ `base_abilities` replaces the whole map rather than merging into it, and a
  # partial one reads as **zero** everywhere it is silent
  # (`Abilities.scores_at/3`). Every caster below needs one ability raised and
  # none of them wants the other five at nothing.
  defp abilities(overrides), do: Map.merge(Build.new().base_abilities, overrides)

  # The block the loader builds from `"repeatable": {"choice": "skill", …}`.
  defp takes(domain) do
    %{choice: domain, distinct?: true, distinct_stated?: true, max_takes: nil, status: "verified"}
  end

  defp worn(%Build{gear: %Gear{} = gear} = build, feats) do
    %Build{build | gear: %Gear{gear | feats: feats}}
  end

  # A context built by hand, so the two values of `requirement_of` can be put to
  # the very same block on the very same build.
  defp context(build, ruleset, requirement_of) do
    %{
      build: build,
      ruleset: ruleset,
      stats: nil,
      level: Build.character_level(build),
      requirement_of: requirement_of
    }
  end

  # Тот же контекст плюс значение, с которым фит берётся: его читает требование
  # владения выбранным оружием. `:none` — фита нет вовсе, значит и значения.
  defp feat_context(build, ruleset, choice) do
    value = if choice == :none, do: nil, else: choice

    build |> context(ruleset, :feat) |> Map.put(:chosen_value, value)
  end

  describe "max_character_level — the first ceiling in the schema" do
    # Every other key is a minimum ("21st level"); this one is a maximum, which
    # is how the wiki writes "can only be taken at 1st level".
    test "compares against the level the feat is picked on", %{ruleset: ruleset} do
      first = Build.new(levels: [:fighter])
      second = Build.new(levels: [:fighter, :fighter])

      assert check(ruleset, %{"max_character_level" => 1}, first) == :ok

      assert check(ruleset, %{"max_character_level" => 1}, second) ==
               {:error, [{:max_character_level, 1}]}
    end

    # The level a feat was picked on is not "how far the build eventually got":
    # a level-1 pick stays legal in a finished 20-level build.
    test "a finished build is asked about the level, not its length", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 20))
      ruleset = with_prereqs(ruleset, %{"max_character_level" => 1})

      assert Rules.validate_feat(build, %{feat: @feat, at: 1}, ruleset) == :ok

      assert Rules.validate_feat(build, %{feat: @feat, at: 2}, ruleset) ==
               {:error, [{:max_character_level, 1}]}
    end

    test "a minimum and a maximum coexist", %{ruleset: ruleset} do
      prereqs = %{"character_level" => 2, "max_character_level" => 3}

      assert {:error, [{:requires_character_level, 2}]} =
               check(ruleset, prereqs, Build.new(levels: [:fighter]))

      assert check(ruleset, prereqs, Build.new(levels: List.duplicate(:fighter, 3))) == :ok

      assert {:error, [{:max_character_level, 3}]} =
               check(ruleset, prereqs, Build.new(levels: List.duplicate(:fighter, 4)))
    end
  end

  describe "casts_spell_level" do
    # source: vanilla/classes.json — the spells_per_day column of each caster's
    # progression table. Wizard 5 has cells of circles 0..3 and none of 4.
    #
    # ⚠ The ability is raised here and it no longer matters — kept exactly so,
    # because it once did. Between 04.08 and 27.08.2026 this test read «the
    # struct's default of 10 is not enough to cast anything above cantrips», and
    # the legality it then called wrong is the legality the game turned out to
    # grant (case AE1). The score stays raised so that the next reader can see
    # this test does not depend on it; the block below asserts that directly.
    test "is read off the class spell table", %{ruleset: ruleset} do
      wizard =
        Build.new(levels: List.duplicate(:wizard, 5), base_abilities: abilities(%{int: 18}))

      assert check(ruleset, %{"casts_spell_level" => 3}, wizard) == :ok

      assert check(ruleset, %{"casts_spell_level" => 4}, wizard) ==
               {:error, [{:requires_spell_level, 4}]}
    end

    test "a non-caster reaches no circle at all", %{ruleset: ruleset} do
      fighter = Build.new(levels: List.duplicate(:fighter, 20))

      assert check(ruleset, %{"casts_spell_level" => 1}, fighter) ==
               {:error, [{:requires_spell_level, 1}]}
    end

    # ⚠ CLAUDE.md §6: both spell tables stop at class level 20, so a Sorcerer 41
    # reaches exactly what a Sorcerer 20 reaches. A feat gated on 9th circle
    # spells must not become takeable by grinding class levels.
    test "the level-20 wall applies", %{ruleset: ruleset} do
      assert Spells.highest_circle(Build.new(levels: List.duplicate(:sorcerer, 20)), ruleset) ==
               Spells.highest_circle(Build.new(levels: List.duplicate(:sorcerer, 41)), ruleset)

      assert Spells.highest_circle(Build.new(levels: List.duplicate(:sorcerer, 17)), ruleset) < 9
    end

    # Multiclassing dilutes the caster, and the table is keyed by *class* level.
    test "only the casting class's own levels count", %{ruleset: ruleset} do
      dip = Build.new(levels: List.duplicate(:wizard, 5) ++ List.duplicate(:fighter, 10))

      assert Spells.highest_circle(dip, ruleset) == 3

      assert check(ruleset, %{"casts_spell_level" => 4}, dip) ==
               {:error, [{:requires_spell_level, 4}]}
    end

    # Cantrips are circle 0, which is also what a non-caster has — no
    # prerequisite in the data asks for cantrips, so the two need not differ.
    test "a bard with cantrips only reaches no first-circle spell", %{ruleset: ruleset} do
      assert Spells.highest_circle(Build.new(levels: [:bard, :bard]), ruleset) == 0
      assert Spells.highest_circle(Build.new(levels: [:bard, :bard, :bard]), ruleset) == 1
    end
  end

  # 🔴 Rewritten twice on 27.08.2026 — task 3.122 and then task 3.124, by two
  # measurements pointing opposite ways. 3.122 took the ability half out of the
  # requirement for all seven casters; 3.124 put it back for the five who are not
  # spontaneous casters, which is the set the source's own sentence names.
  #
  # source: `fandom:Spell focus`, Notes, revid 69073 — «**Spontaneous casters
  # (bards and sorcerers)** can take this feat without being able to cast first
  # level spells as long as their class level qualifies for at least 0 level one
  # spell slots (that is, even if their casting ability is too low to actually
  # cast a level one spell)».
  #
  # source: Dan, тестовый сервер, 27.08.2026 — «бард 4 с харизмой 11 дает взять
  # empower spell» и «у барда 3 empower spell нет» (`GAME_CHECKS.md` AE1);
  # «я прокачал волшебника аж до 8 уровня с 11 интеллекта и 2 круг так и не
  # появился. И empower spell так и не появился» (AE2).
  describe "casts_spell_level — напечатанный ноль засчитывается СПОНТАННОМУ кастеру" do
    # 🔴 The measurement itself, both sides. One side alone proves nothing: with
    # only the Bard 4 the rule could be "any level of a casting class", and with
    # only the Bard 3 it could be the old one.
    #
    # Bard 4 is the first row of the bard table printing a second-circle cell
    # and it prints `0`; Bard 3 has no second-circle cell at all. Charisma 11 is
    # one short of the 12 that casting a second-circle spell needs, so the
    # engine plainly asked the cell and not the score.
    test "бард 4 с харизмой 11 берёт Empower Spell, бард 3 — нет",
         %{ruleset: ruleset} do
      bard = fn levels ->
        Build.new(levels: List.duplicate(:bard, levels), base_abilities: abilities(%{cha: 11}))
      end

      assert check(ruleset, %{"casts_spell_level" => 2}, bard.(4)) == :ok

      assert check(ruleset, %{"casts_spell_level" => 2}, bard.(3)) ==
               {:error, [{:requires_spell_level, 2}]}

      # The cell the answer turns on, read straight off the data, so a change to
      # the bard table shows up here as a failing table rather than as a silently
      # different verdict.
      assert %{2 => 0} = ruleset.classes[:bard].spells_per_day[4]
      refute Map.has_key?(ruleset.classes[:bard].spells_per_day[3], 2)
    end

    # 🔴 The observation that kills the alternative reading, and it is not a
    # measurement but the engine's own print: `test/fixtures/game_logs/aley.log`
    # is a Bard 9 with charisma 11 who **holds** `Empower Spell`, and a Bard 9's
    # second-circle cell is **3**, not zero.
    #
    # `GAME_CHECKS.md` AE2 offered, for a negative answer, a rule with no
    # spontaneity in it — «the row names the circle and (the cell is zero or the
    # ability reaches 10 + circle)». It explains the Bard 4, the Bard 3 and the
    # Wizard 8 below, and it is false here. «At least 0» is not «exactly 0».
    test "бард 9 с харизмой 11 — ячейка НЕнулевая, и фит всё равно доступен",
         %{ruleset: ruleset} do
      bard = Build.new(levels: List.duplicate(:bard, 9), base_abilities: abilities(%{cha: 11}))

      assert %{2 => 3} = ruleset.classes[:bard].spells_per_day[9]
      assert Spells.minimum_ability_score(ruleset, 2) == 12
      assert check(ruleset, %{"casts_spell_level" => 2}, bard) == :ok
    end

    # 🔴 The other side of the same day, and the one 3.122 got wrong: a **full**
    # caster with a **non-zero** cell whose ability is a point short is refused
    # in the game. Between 3.122 and 3.124 we answered `:ok` here — a false
    # legality, the direction a player cannot discover from inside the tool.
    test "волшебник 8 с интеллектом 11 фит НЕ берёт, с 12 — берёт",
         %{ruleset: ruleset} do
      wizard = fn int ->
        Build.new(levels: List.duplicate(:wizard, 8), base_abilities: abilities(%{int: int}))
      end

      # The cell is real, so the refusal below is about the ability and about
      # nothing else.
      assert %{2 => 3} = ruleset.classes[:wizard].spells_per_day[8]

      assert check(ruleset, %{"casts_spell_level" => 2}, wizard.(11)) ==
               {:error, [{:requires_ability, :int, 12}]}

      assert check(ruleset, %{"casts_spell_level" => 2}, wizard.(12)) == :ok
    end

    # And the same pair through the three readings themselves, so the split is
    # pinned and not just its consequence: the casting reading says the Bard 4
    # does **not** cast the circle, and the answer above is `:ok` regardless.
    test "три функции отвечают по-разному об одном и том же барде",
         %{ruleset: ruleset} do
      bard = Build.new(levels: List.duplicate(:bard, 4), base_abilities: abilities(%{cha: 11}))

      assert Spells.casters_offered_circle(bard, ruleset, 2) == [:bard]
      assert Spells.spontaneous_casters_offered_circle(bard, ruleset, 2) == [:bard]
      assert Spells.casters_for_circle(bard, ruleset, 2) == []

      # Negative control on the wider reading, so `[:bard]` above is about the
      # printed zero and not about the function answering `[:bard]` always.
      three = Build.new(levels: List.duplicate(:bard, 3), base_abilities: abilities(%{cha: 11}))
      assert Spells.casters_offered_circle(three, ruleset, 2) == []

      # And the narrowing itself: the wizard's row names the circle too, and he
      # is not in the spontaneous answer.
      wizard =
        Build.new(levels: List.duplicate(:wizard, 8), base_abilities: abilities(%{int: 11}))

      assert Spells.casters_offered_circle(wizard, ruleset, 2) == [:wizard]
      assert Spells.spontaneous_casters_offered_circle(wizard, ruleset, 2) == []
    end

    # ⚠ The generalisation over circles, stated as a test so it stays visible.
    # For a spontaneous caster the ability is not asked at **any** circle:
    # measured at circle 2 on the bard, and applying it at some circles and not
    # others would be an invention.
    test "у спонтанного кастера характеристика не гейтит ни один круг",
         %{ruleset: ruleset} do
      dull =
        Build.new(levels: List.duplicate(:sorcerer, 20), base_abilities: abilities(%{cha: 8}))

      for circle <- 1..9 do
        assert check(ruleset, %{"casts_spell_level" => circle}, dull) == :ok
      end

      # Negative control: the table still refuses, so the row of `:ok` above is
      # about the ability being ignored and not about the key being ignored.
      short =
        Build.new(levels: List.duplicate(:sorcerer, 5), base_abilities: abilities(%{cha: 30}))

      assert check(ruleset, %{"casts_spell_level" => 4}, short) ==
               {:error, [{:requires_spell_level, 4}]}
    end

    # ⚠ And the mirror of it for a caster who prepares: the ability gates every
    # circle, and the refusal names the score the player has to reach.
    test "у готовящего кастера характеристика гейтит каждый круг",
         %{ruleset: ruleset} do
      dull = Build.new(levels: List.duplicate(:wizard, 20), base_abilities: abilities(%{int: 10}))

      for circle <- 1..9 do
        assert check(ruleset, %{"casts_spell_level" => circle}, dull) ==
                 {:error, [{:requires_ability, :int, 10 + circle}]}
      end

      # Positive control: the same twenty levels with an intelligence that
      # clears every bar answer `:ok` everywhere.
      bright =
        Build.new(levels: List.duplicate(:wizard, 20), base_abilities: abilities(%{int: 19}))

      for circle <- 1..9 do
        assert check(ruleset, %{"casts_spell_level" => circle}, bright) == :ok
      end
    end

    # ⚠ The whole reason the check is written per class: splitting it into "some
    # class has the slots" and "some ability is high enough" would clear this
    # build, which casts nothing above the first circle. The sorcerer is
    # spontaneous, so his own row is asked without an ability — and his row
    # reaches circle 1, not circle 9.
    test "слоты и характеристика — одного класса, а не разных", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 20) ++ [:sorcerer],
          base_abilities: abilities(%{int: 10, cha: 30})
        )

      assert Spells.highest_circle(build, ruleset) == 9

      assert check(ruleset, %{"casts_spell_level" => 9}, build) ==
               {:error, [{:requires_ability, :int, 19}]}

      # Positive control: the same build with the *wizard's* ability raised.
      qualified = %{build | base_abilities: abilities(%{int: 19, cha: 30})}
      assert check(ruleset, %{"casts_spell_level" => 9}, qualified) == :ok
    end

    # «both a base … and a modified … score»: gear may only lift the second, so
    # what binds is the base. A future penalty from gear would bind the other
    # way, which is why both are compared rather than just the naked one.
    test "вещи не поднимают базовое значение над порогом", %{ruleset: ruleset} do
      geared =
        Build.new(
          levels: List.duplicate(:wizard, 20),
          base_abilities: abilities(%{int: 18}),
          gear: %BuildCalculator.Rules.Gear{abilities: %{int: 12}}
        )

      assert check(ruleset, %{"casts_spell_level" => 9}, geared) ==
               {:error, [{:requires_ability, :int, 19}]}

      # Positive control: the gear is real and does reach the stats.
      assert Rules.compute(geared, ruleset).abilities.int == 30
    end

    # The half-casters. Their first circle is a printed zero for two class
    # levels, and they are **not** spontaneous, so the printed zero does nothing
    # for them by itself — what opens the circle at class level 4 is the bonus
    # slot a wisdom of 12 turns that zero into (task 3.70).
    #
    # ⚠ Задача 3.122 давала им круг с 4-го при ЛЮБОЙ мудрости, включая 10.
    # 3.124 это сняла: правило источника про спонтанных, а паладин готовит
    # заклинания. Числа — в отчёте задачи.
    test "паладин и рейнджер: круг с 4-го при мудрости 12, с 6-го при 11, при 10 — никогда",
         %{ruleset: ruleset} do
      for class <- [:paladin, :ranger] do
        build = fn levels, wisdom ->
          Build.new(
            levels: List.duplicate(class, levels),
            base_abilities: abilities(%{wis: wisdom})
          )
        end

        # Wisdom 12: the bonus slot makes the printed zero a real slot, and 12
        # clears the 11 the first circle needs.
        assert check(ruleset, %{"casts_spell_level" => 1}, build.(4, 12)) == :ok

        # Wisdom 11 clears the bar but earns no bonus slot, so the zero stays a
        # zero until the table itself prints a one at class level 6.
        assert check(ruleset, %{"casts_spell_level" => 1}, build.(4, 11)) ==
                 {:error, [{:requires_spell_level, 1}]}

        assert check(ruleset, %{"casts_spell_level" => 1}, build.(6, 11)) == :ok

        # Wisdom 10 never casts at all — «a base wisdom score of 10 + the
        # spell's level».
        assert check(ruleset, %{"casts_spell_level" => 1}, build.(20, 10)) ==
                 {:error, [{:requires_ability, :wis, 11}]}

        # And the cells the three answers turn on.
        assert %{1 => 0} = ruleset.classes[class].spells_per_day[4]
        assert %{1 => 1} = ruleset.classes[class].spells_per_day[6]
      end
    end

    # A prepared caster whose ability nobody names is undecidable, never "fine".
    # ⚠ Восстановлено 3.124 вместе с самой проверкой: задача 3.122 сняла её
    # и написала, что форму по-прежнему заводит загрузчик, — верно, но это
    # другой вопрос («в данных не назвали») и другой момент («при сборке»).
    test "готовящий класс без названной характеристики — гэп, а не пропуск",
         %{ruleset: ruleset} do
      silent = put_in(ruleset.classes[:wizard].casting_ability, nil)

      build =
        Build.new(levels: List.duplicate(:wizard, 20), base_abilities: abilities(%{int: 19}))

      # Positive control: with the field in place the same build passes.
      assert check(ruleset, %{"casts_spell_level" => 9}, build) == :ok

      assert check(silent, %{"casts_spell_level" => 9}, build) ==
               {:error, [{:missing_data, {:casting_ability, :wizard}}]}
    end
  end

  # Кто спонтанный — свойство RULESET'А, а не имя класса в коде ядра. Обе
  # стороны проверяются подменой данных, а не чтением исходника: иначе «список
  # лежит в данных» остаётся утверждением, которое ничем не держится.
  describe "casts_spell_level — множество спонтанных приходит из данных" do
    test "ruleset без записи не даёт исключение НИКОМУ", %{ruleset: ruleset} do
      without = put_in(ruleset.casting.spontaneous, nil)
      bard = Build.new(levels: List.duplicate(:bard, 4), base_abilities: abilities(%{cha: 11}))

      assert Spells.spontaneous_casters(without) == MapSet.new()

      # Строгая сторона: ложная НЕлегальность, которую игрок хотя бы видит.
      assert check(without, %{"casts_spell_level" => 2}, bard) ==
               {:error, [{:requires_spell_level, 2}]}

      # Positive control: тот же билд на настоящем ruleset'е проходит.
      assert check(ruleset, %{"casts_spell_level" => 2}, bard) == :ok
    end

    test "ruleset, объявивший волшебника спонтанным, снимает с него требование",
         %{ruleset: ruleset} do
      wizard =
        Build.new(levels: List.duplicate(:wizard, 8), base_abilities: abilities(%{int: 11}))

      assert check(ruleset, %{"casts_spell_level" => 2}, wizard) ==
               {:error, [{:requires_ability, :int, 12}]}

      spontaneous_wizard =
        put_in(ruleset.casting.spontaneous, MapSet.new([:bard, :sorcerer, :wizard]))

      assert check(spontaneous_wizard, %{"casts_spell_level" => 2}, wizard) == :ok
    end
  end

  # The casting rule itself, asserted against `Rules.Spells` rather than through
  # a feat. ⚠️ Здесь стояло «правило, которое блок выше спрашивать перестал»
  # (3.122) — это верно ровно наполовину и с 3.124 переписано: спрашивать его
  # перестал спонтанный кастер, а готовящий спрашивает по-прежнему. Отдельный
  # блок остаётся нужным: «умеет ли персонаж кастовать круг» — вопрос про каст,
  # и его ответ не совпадает с ответом про доступность фита ни у барда 4
  # (кастовать не умеет, фит есть), ни у волшебника 8 с интеллектом 11.
  #
  # source: fandom «Ability score» revid 71148 — «the caster must have both a
  # ''base'' casting ability score and a modified casting ability score of at
  # least 10 + spell level»; the ability itself off each class page's
  # `primary ability` label (`vanilla/classes.json` → `casting_ability`), the
  # 10 + 1-per-circle out of `vanilla/spellcasting.json`.
  describe "«кастует ли персонаж круг» — вопрос отдельный от требования фита" do
    # ⚠ The moduledoc's own example, kept because it is the one that shows why
    # the two halves must never be mixed **across classes**: this build casts
    # nothing above the first circle, and asking "some class has the slots" and
    # "some ability is high enough" separately would say it casts ninth-circle
    # spells.
    test "Wizard 20 / Sorcerer 1, интеллект 10 и харизма 20 не кастует 9-й круг",
         %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:wizard, 20) ++ [:sorcerer],
          base_abilities: abilities(%{int: 10, cha: 30})
        )

      minimum = Spells.minimum_ability_score(ruleset, 9)
      assert minimum == 19

      # The class with the slots is the wizard, and it is the wizard's own
      # ability that must clear the bar — the sorcerer's 30 is not his.
      assert [%{class: :wizard, ability: :int}] = Spells.casters_for_circle(build, ruleset, 9)
      assert Rules.compute(build, ruleset).abilities.int < minimum

      # Positive control: raise the *wizard's* ability and the same build casts.
      qualified = %{build | base_abilities: abilities(%{int: 19, cha: 30})}
      assert Rules.compute(qualified, ruleset).abilities.int >= minimum
    end

    # ⚠ Два ответа расходятся, и это не разные данные, а разные вопросы. Бард 4
    # круг не кастует и фит получает; волшебник 8 с интеллектом 11 не кастует
    # и фита не получает. Оба под тестом рядом, чтобы «эти две функции про одно
    # и то же» нельзя было предположить.
    test "«кастует» и «доступен фит» — разные ответы на одном билде",
         %{ruleset: ruleset} do
      bard = Build.new(levels: List.duplicate(:bard, 4), base_abilities: abilities(%{cha: 11}))

      assert Spells.casters_for_circle(bard, ruleset, 2) == []
      assert check(ruleset, %{"casts_spell_level" => 2}, bard) == :ok

      wizard =
        Build.new(levels: List.duplicate(:wizard, 8), base_abilities: abilities(%{int: 11}))

      assert [%{class: :wizard}] = Spells.casters_for_circle(wizard, ruleset, 2)

      assert check(ruleset, %{"casts_spell_level" => 2}, wizard) ==
               {:error, [{:requires_ability, :int, 12}]}
    end

    # `nil` is "the file does not say", and then the rule is not checked rather
    # than guessed — the one promise `minimum_ability_score/2` makes.
    test "без записи в данных правило не проверяется, а не выдумывается",
         %{ruleset: ruleset} do
      without = put_in(ruleset.casting.ability_minimum, nil)

      assert Spells.minimum_ability_score(without, 9) == nil
      assert Spells.minimum_ability_score(ruleset, 9) == 19
    end
  end

  describe "casts_spell_level — Pale Master lends its host slot levels" do
    # ⚠ The wiki's own worked example, and the strongest pin available: «a level
    # 10 sorcerer / 19 pale master has the same spells per day as a level 20
    # sorcerer» (fandom «Pale master» revid 71581). Compared against a real
    # Sorcerer 20 rather than against a transcribed row, so a change to the
    # sorcerer table cannot make this pass by moving both sides.
    test "the page's own example: Sorcerer 10 / Pale Master 19", %{ruleset: ruleset} do
      pair = Build.new(levels: List.duplicate(:sorcerer, 10) ++ List.duplicate(:pale_master, 19))
      pure = Build.new(levels: List.duplicate(:sorcerer, 20))

      assert [
               %{
                 slots: advanced,
                 table_level: 20,
                 advanced_levels: 10,
                 advanced_by: [:pale_master]
               }
             ] =
               Spells.per_day(pair, ruleset)

      assert [%{slots: ^advanced}] = Spells.per_day(pure, ruleset)

      # Negative control: without the pale master levels the same sorcerer is
      # ten rows short.
      assert Spells.highest_circle(Build.new(levels: List.duplicate(:sorcerer, 10)), ruleset) < 9
      assert Spells.highest_circle(pair, ruleset) == 9
    end

    # «Upon reaching pale master levels 1, 3, 5, 7, and 9» / «at every odd pale
    # master level». The example above cannot tell the two readings apart — both
    # hit the level-20 ceiling there — so this is where it is settled.
    test "odd class levels only, which the example alone does not prove",
         %{ruleset: ruleset} do
      for {pm, expected} <- [{1, 1}, {2, 1}, {3, 2}, {5, 3}, {19, 10}, {30, 15}] do
        build = Build.new(levels: [:sorcerer] ++ List.duplicate(:pale_master, pm))
        assert Spells.advancement(build, ruleset).hosts.sorcerer.levels == expected
      end
    end

    # «He does not learn any new spells through this ability … only knows as many
    # spells as a level 10 sorcerer.» Slots move, known spells do not.
    test "known spells are not advanced", %{ruleset: ruleset} do
      bard = Build.new(levels: List.duplicate(:bard, 4))
      with_pm = Build.new(levels: List.duplicate(:bard, 4) ++ List.duplicate(:pale_master, 30))

      assert Spells.slots(bard, ruleset) == Spells.slots(with_pm, ruleset)

      # Positive control: the slots per day *did* move, so the equality above is
      # about known spells and not about nothing happening.
      assert Spells.highest_circle(bard, ruleset) < Spells.highest_circle(with_pm, ruleset)
    end

    # «but has a caster level of only 10» — the one number the class explicitly
    # does not advance, and the one the core refuses to work out at all.
    test "caster level is still refused", %{ruleset: ruleset} do
      pair = Build.new(levels: List.duplicate(:sorcerer, 10) ++ List.duplicate(:pale_master, 19))

      assert check(ruleset, %{"caster_level" => 11}, pair) ==
               {:error, [{:missing_data, {:caster_level, 11}}]}
    end

    # «his highest caster class (bard, sorcerer or wizard)» — a divine caster is
    # not on the list, and adding one by symmetry is exactly the invention §3
    # forbids.
    test "a divine caster is not a host", %{ruleset: ruleset} do
      cleric = Build.new(levels: List.duplicate(:cleric, 10) ++ List.duplicate(:pale_master, 19))

      assert Spells.advancement(cleric, ruleset).hosts == %{}

      assert [%{class: :cleric, table_level: 10, advanced_levels: 0}] =
               Spells.per_day(cleric, ruleset)
    end

    test "the host is the arcane class with the most levels", %{ruleset: ruleset} do
      build =
        Build.new(
          levels:
            List.duplicate(:bard, 8) ++
              List.duplicate(:wizard, 3) ++ List.duplicate(:pale_master, 10)
        )

      assert Spells.advancement(build, ruleset).hosts == %{
               bard: %{levels: 5, from: [:pale_master]}
             }
    end

    # Nothing in any source settles a tie, so neither host is advanced and the
    # class is named. Understating refuses rather than grants, which is the safe
    # direction — but it is still an answer we do not have.
    test "two hosts tied for highest advance neither, and it is said out loud",
         %{ruleset: ruleset} do
      tied =
        Build.new(
          levels:
            List.duplicate(:bard, 5) ++
              List.duplicate(:wizard, 5) ++ List.duplicate(:pale_master, 10),
          base_abilities: abilities(%{int: 20, cha: 20})
        )

      assert Spells.advancement(tied, ruleset) == %{hosts: %{}, undecided: [:pale_master]}

      assert check(ruleset, %{"casts_spell_level" => 9}, tied) ==
               {:error, [{:missing_data, {:caster_advancement, :pale_master}}]}
    end

    test "pale master levels with no host class advance nothing", %{ruleset: ruleset} do
      alone = Build.new(levels: List.duplicate(:pale_master, 19))

      assert Spells.advancement(alone, ruleset) == %{hosts: %{}, undecided: []}
      assert Spells.per_day(alone, ruleset) == []
    end

    # «up to the maximum spells per day (at caster class level 20)» — the ceiling
    # is the host table's own last row, so the wall still stands.
    test "the lent levels stop at the host table's last row", %{ruleset: ruleset} do
      over = Build.new(levels: List.duplicate(:sorcerer, 20) ++ List.duplicate(:pale_master, 19))

      assert [%{table_level: 20, past_table?: true, advanced_levels: 10}] =
               Spells.per_day(over, ruleset)
    end

    # ⚠ «Бледный Призыватель» (Бард 4 / Pale Master 30, вики Сиалы revid 18469).
    # Таблица барда доезжает до 19-й строки, а она кончается шестым кругом —
    # девятого этот билд не достигает и не достигнет, сколько бы уровней Бледный
    # мастер ни продвинул.
    #
    # ⚠️ Здесь стояло «страница, чьи пять эпических заклинаний модель отбивает»
    # — устарело 15.08.2026 (задача 3.31): эпические заклинания девятого круга
    # НЕ требуют, их страницы прямо это опровергают, и пять отказов сняты. Тест
    # остаётся, потому что `casts_spell_level` никуда не делся у других фитов
    # (`epic_spell_focus`, `automatic_quicken_spell` и ещё двое), и проверяет он
    # ровно то же: продвижение слотов считается, а девятый круг барду недоступен.
    test "Бледный Призыватель: the slots do advance and the ninth circle is still out of reach",
         %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:bard, 4) ++ List.duplicate(:pale_master, 30),
          base_abilities: abilities(%{cha: 25})
        )

      assert Spells.advancement(build, ruleset).hosts.bard.levels == 15
      assert [%{class: :bard, class_level: 4, table_level: 19}] = Spells.per_day(build, ruleset)
      assert Spells.highest_circle(build, ruleset) == 6

      assert check(ruleset, %{"casts_spell_level" => 9}, build) ==
               {:error, [{:requires_spell_level, 9}]}

      # Положительный контроль: круг, до которого таблица доезжает, проходит —
      # значит отказ выше про девятый круг, а не про сломанный расчёт.
      assert check(ruleset, %{"casts_spell_level" => 6}, build) == :ok
    end
  end

  describe "qualifying_class_levels — the requirement about THIS level's class" do
    # `fandom:Epic spell: mummy dust` (revid 62570) и ещё пять страниц, дословно:
    # «The actual prerequisite is not the ability to cast level 9 spells, but
    # being an [[epic class|epic]] [[cleric]], [[druid]], [[sorcerer]], or
    # [[wizard]], or having at least 15 [[pale master]] levels. Furthermore, this
    # feat can only be chosen when gaining a level in the qualifying class».
    #
    # Пороги — `fandom:Epic class` (revid 40911): «21 levels for a base class, or
    # 11 levels for a prestige class», и 15 для Бледного мастера прямо из правила
    # выше. Здесь они в фикстуре, а не в коде.
    @qualifies %{"cleric" => 21, "sorcerer" => 21, "wizard" => 21, "pale_master" => 15}

    # Таблица: билд, уровень взятия, ожидание. Один и тот же ключ, четыре разных
    # ответа — и все четыре нужны, потому что каждый закрывает свою ошибку.
    @cases [
      # Класс уровня квалифицирует — единственный случай, когда фит законен.
      {"эпический волшебник берёт на своём уровне", List.duplicate(:wizard, 21), 21, :ok},
      # Тот же билд на 20-м: класс тот, уровней мало. Граница ровно на 21.
      {"волшебник 20 — ещё не эпический", List.duplicate(:wizard, 21), 20,
       {:error, [{:requires_class_level, :wizard, 21}]}},
      # ⚠️ ГЛАВНЫЙ кейс второй половины правила: право есть (волшебник 21), но
      # слот тратится на уровне клирика, а клириковских уровней 5. Без проверки
      # «класс ЭТОГО уровня» билд прошёл бы — это ложная легальность, ради
      # которой вторая половина и записана.
      {"волшебник 21 → клирик 5, на клериковском уровне",
       List.duplicate(:wizard, 21) ++ List.duplicate(:cleric, 5), 26,
       {:error, [{:requires_class_level, :cleric, 21}]}},
      # Тот же билд, но уровень волшебничий — законно. Пара с кейсом выше
      # показывает, что ответ движется с УРОВНЕМ, а не с составом билда.
      {"тот же билд, взято на волшебничьем уровне",
       List.duplicate(:wizard, 21) ++ List.duplicate(:cleric, 5), 21, :ok},
      # Класса нет в таблице вовсе — другая форма отказа, называющая, на чьём
      # уровне это берут.
      {"на воинском уровне не берётся вовсе",
       List.duplicate(:wizard, 21) ++ List.duplicate(:fighter, 5), 26,
       {:error, [{:requires_leveling_as, [:cleric, :pale_master, :sorcerer, :wizard]}]}},
      # Замер Dan 15.08.2026 (`GAME_CHECKS.md` E3): бард 10 / ПМ 15 — игра
      # предлагает `Epic spell: mummy dust`, хотя бард кастует максимум 6-й круг.
      {"замер Dan: бард 10 / Бледный мастер 15",
       List.duplicate(:bard, 10) ++ List.duplicate(:pale_master, 15), 25, :ok},
      # На уровень раньше — порог Бледного мастера 15, а не общий престижный 11.
      {"Бледный мастер 14 — порог 15, а не 11",
       List.duplicate(:bard, 10) ++ List.duplicate(:pale_master, 15), 24,
       {:error, [{:requires_class_level, :pale_master, 15}]}},
      # Мультикласс на четыре класса и уровень 41 — кап Сиалы. Класс последнего
      # уровня квалифицирует, остальные три ничего не портят.
      {"четыре класса, 41-й уровень взят волшебником",
       List.duplicate(:fighter, 10) ++
         List.duplicate(:rogue, 5) ++ List.duplicate(:pale_master, 5) ++ [:wizard], 21,
       {:error, [{:requires_class_level, :wizard, 21}]}}
    ]

    for {title, levels, at, expected} <- @cases do
      test title, %{ruleset: ruleset} do
        build = Build.new(levels: Enum.take(unquote(levels), unquote(at)))
        ruleset = with_prereqs(ruleset, %{"qualifying_class_levels" => @qualifies})

        assert Rules.validate_feat(build, %{feat: @feat, at: unquote(at)}, ruleset) ==
                 unquote(Macro.escape(expected))
      end
    end

    # Обе половины правила в одном ключе намеренно (см. moduledoc `Prereqs`):
    # порознь их удовлетворяют РАЗНЫЕ классы, и билд прошёл бы обе, нарушая
    # правило целиком. Этот тест — контроль на то, что ключ так и не распался
    # на «есть класс в билде» плюс «уровень взят на каком-то из списка».
    test "the two halves are one condition, not two", %{ruleset: ruleset} do
      # Половина «в билде есть квалифицирующий класс» выполнена волшебником 21.
      build = Build.new(levels: List.duplicate(:wizard, 21) ++ [:cleric])
      ruleset = with_prereqs(ruleset, %{"qualifying_class_levels" => @qualifies})

      # Половина «уровень взят на классе из списка» выполнена клериком.
      assert Build.class_at(build, 22) == :cleric
      assert Map.has_key?(@qualifies, "cleric")

      # И всё равно отказ: квалифицировать должен ТОТ ЖЕ класс.
      assert Rules.validate_feat(build, %{feat: @feat, at: 22}, ruleset) ==
               {:error, [{:requires_class_level, :cleric, 21}]}
    end

    # Значение, которое схема прочитать не может, — требование есть и не
    # проверено, значит названо, а не пропущено. Та же форма, что у всех
    # остальных ключей этого модуля.
    test "a malformed threshold is named rather than skipped", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:wizard, 21))

      assert check(ruleset, %{"qualifying_class_levels" => %{"wizard" => "epic"}}, build) ==
               {:error, [{:missing_data, {:prerequisite, :qualifying_class_levels}}]}

      assert check(ruleset, %{"qualifying_class_levels" => %{}}, build) ==
               {:error, [{:missing_data, {:prerequisite, :qualifying_class_levels}}]}
    end

    # Шесть настоящих записей ruleset'а, а не фикстура: правило доехало из
    # `vanilla/feat_requirements.json` до фита, и `casts_spell_level` там больше
    # нет — страницы всех шести говорят, что это требование неверно.
    test "the six epic spells carry it instead of casts_spell_level", %{ruleset: ruleset} do
      six = [
        :epic_spell_dragon_knight,
        :epic_spell_epic_mage_armor,
        :epic_spell_epic_warding,
        :epic_spell_greater_ruin,
        :epic_spell_hellball,
        :epic_spell_mummy_dust
      ]

      for id <- six do
        prereqs = ruleset.feats[id].prereqs

        refute Map.has_key?(prereqs, "casts_spell_level"), "#{id} still asks for the ninth circle"
        assert Map.get(prereqs["qualifying_class_levels"], "pale_master") == 15

        # И ни у одного не осталось сырого остатка: у `epic_warding` фрагмент
        # «epic level caster» — это ровно то же предложение, и он прочитан.
        assert Map.get(prereqs, "unparsed", []) == []
      end
    end

    # ⚠️ Замер сделан на билде, у которого ВСЕ эпические уровни — Бледный
    # мастер, поэтому вторую половину правила он подтвердить не мог: любой слот
    # там «на уровне квалифицирующего класса» по построению. Половина взята из
    # источника, и вот её цена, названная числом: на билде с двумя кастерами мы
    # СТРОЖЕ игры, если на Сиале этого ограничения нет.
    test "the half the measurement could not confirm is the half that refuses", %{
      ruleset: ruleset
    } do
      # Тот же персонаж, что замерял Dan, плюс один уровень волшебника сверху.
      levels = List.duplicate(:bard, 10) ++ List.duplicate(:pale_master, 15) ++ [:wizard]

      # Spellcraft 15 — второе требование этого фита, и его надо закрыть, чтобы
      # в причинах остался только вопрос уровня.
      build = Build.new(levels: levels, skills: %{20 => %{spellcraft: 15}})

      # На уровне Бледного мастера — законно, и это измерено.
      assert Rules.validate_feat(
               build,
               %{feat: :epic_spell_mummy_dust, at: 25},
               ruleset
             ) == :ok

      # На волшебничьем уровне следом — отказ, и он ТОЛЬКО из источника.
      assert {:error, reasons} =
               Rules.validate_feat(build, %{feat: :epic_spell_mummy_dust, at: 26}, ruleset)

      assert {:requires_class_level, :wizard, 21} in reasons
    end
  end

  describe "caster_level is not worked out" do
    # Nothing under priv/rules/ states how caster level is derived — not the
    # single-class identity, not the multiclass case, not which prestige classes
    # advance it. "Probably the class level" is exactly the plausible guess the
    # project forbids, so the feat is never cleared on it.
    test "returns a gap even for a pure caster at the cap", %{ruleset: ruleset} do
      for levels <- [1, 20, 41] do
        build = Build.new(levels: List.duplicate(:wizard, levels))

        assert check(ruleset, %{"caster_level" => 3}, build) ==
                 {:error, [{:missing_data, {:caster_level, 3}}]}
      end
    end

    test "the required number travels with the gap", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:wizard, 20))

      assert check(ruleset, %{"caster_level" => 5}, build) ==
               {:error, [{:missing_data, {:caster_level, 5}}]}
    end
  end

  describe "any_of — the one disjunction" do
    @branches [%{"race" => ["dwarf"]}, %{"class_levels" => %{"pale_master" => 3}}]

    test "one satisfied branch clears it", %{ruleset: ruleset} do
      dwarf = Build.new(levels: [:fighter], race: :dwarf)
      caster = Build.new(levels: List.duplicate(:pale_master, 3), race: :elf)

      assert check(ruleset, %{"any_of" => @branches}, dwarf) == :ok
      assert check(ruleset, %{"any_of" => @branches}, caster) == :ok
    end

    # Branches stay grouped: "dwarf" and "pale master 3" are alternatives to each
    # other, and a flat list of tuples would read as two demands.
    test "no branch satisfied reports one list per branch", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter], race: :elf)

      assert check(ruleset, %{"any_of" => @branches}, build) ==
               {:error,
                [
                  {:requires_any_of,
                   [
                     [{:requires_race, [:dwarf]}],
                     [{:requires_class_level, :pale_master, 3}]
                   ]}
                ]}
    end

    test "a branch with several requirements keeps them together", %{ruleset: ruleset} do
      branches = [
        %{"race" => ["dwarf"], "base_attack_bonus" => 7},
        %{"class_levels" => %{"rogue" => 2}}
      ]

      build = Build.new(levels: [:fighter], race: :elf)

      assert {:error, [{:requires_any_of, [first, second]}]} =
               check(ruleset, %{"any_of" => branches}, build)

      assert first == [{:requires_bab, 7}, {:requires_race, [:dwarf]}]
      assert second == [{:requires_class_level, :rogue, 2}]
    end

    # An alternative whose branch cannot be decided is refused, but visibly so:
    # the gap sits inside that branch instead of being swallowed by a pass.
    test "an undecidable branch keeps its gap and does not pass", %{ruleset: ruleset} do
      branches = [%{"caster_level" => 3}, %{"race" => ["dwarf"]}]
      build = Build.new(levels: List.duplicate(:wizard, 20), race: :elf)

      assert check(ruleset, %{"any_of" => branches}, build) ==
               {:error,
                [
                  {:requires_any_of,
                   [
                     [{:missing_data, {:caster_level, 3}}],
                     [{:requires_race, [:dwarf]}]
                   ]}
                ]}
    end

    test "nesting works, because a branch is a requirement block", %{ruleset: ruleset} do
      branches = [%{"any_of" => [%{"race" => ["dwarf"]}, %{"race" => ["gnome"]}]}]

      assert check(ruleset, %{"any_of" => branches}, Build.new(race: :gnome)) == :ok

      assert {:error, [{:requires_any_of, [[{:requires_any_of, _}]]}]} =
               check(ruleset, %{"any_of" => branches}, Build.new(race: :elf))
    end

    # "One of nothing" is a broken record, not a rule that refuses everybody.
    test "an empty list is named as missing data", %{ruleset: ruleset} do
      assert check(ruleset, %{"any_of" => []}, Build.new(levels: [:fighter])) ==
               {:error, [{:missing_data, {:prerequisite, :any_of}}]}
    end
  end

  describe "the rest of the block still conjoins" do
    test "every unmet key is reported at once, in a stable order", %{ruleset: ruleset} do
      prereqs = %{
        "character_level" => 21,
        "base_attack_bonus" => 7,
        "abilities" => %{"str" => 13},
        "race" => ["dwarf"],
        "feats" => ["dodge"],
        "skills" => %{"discipline" => 5},
        "class_levels" => %{"rogue" => 2}
      }

      build = Build.new(levels: [:wizard], race: :elf)

      assert check(ruleset, prereqs, build) ==
               {:error,
                [
                  {:requires_character_level, 21},
                  {:requires_bab, 7},
                  {:requires_ability, :str, 13},
                  {:requires_race, [:dwarf]},
                  {:requires_feat, :dodge},
                  {:requires_skill_ranks, :discipline, 5},
                  {:requires_class_level, :rogue, 2}
                ]}
    end

    test "a build that satisfies everything passes", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 21),
          race: :dwarf,
          base_abilities: %{str: 13, dex: 10, con: 10, int: 10, wis: 10, cha: 10},
          feats: %{1 => %{general: :dodge}},
          skills: %{1 => %{discipline: 5}}
        )

      prereqs = %{
        "character_level" => 21,
        "base_attack_bonus" => 7,
        "abilities" => %{"str" => 13},
        "race" => ["dwarf"],
        "feats" => ["dodge"],
        "skills" => %{"discipline" => 5}
      }

      assert check(ruleset, prereqs, build) == :ok
    end

    # Same rule as for a class: a feat the build was handed for free counts, or a
    # Fighter would be asked to take the Toughness Siala already gave him.
    test "a class-granted feat satisfies a feat requirement", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])

      assert MapSet.member?(Build.granted_feats(build, ruleset, 1), :toughness)
      assert check(ruleset, %{"feats" => ["toughness"]}, build) == :ok
    end

    test "a key the interpreter does not know is left to the data layer", %{ruleset: ruleset} do
      assert check(ruleset, %{"spellcasting" => "able to cast arcane spells"}, Build.new()) == :ok
    end

    # A key that is really there with a value the schema cannot read is named,
    # not dropped: the requirement exists and went unchecked.
    test "a malformed value is named rather than ignored", %{ruleset: ruleset} do
      assert check(ruleset, %{"base_attack_bonus" => "+7"}, Build.new()) ==
               {:error, [{:missing_data, {:prerequisite, :base_attack_bonus}}]}
    end

    # A feat's block reaches the core exactly as the parser wrote it, and the
    # data layer normalises alignment phrases for classes only. An English
    # phrase is therefore unreadable here, and says so.
    test "an alignment left as a wiki phrase is a gap", %{ruleset: ruleset} do
      lawful = Build.new(levels: [:fighter], alignment: :lawful_good)

      assert check(ruleset, %{"alignment" => "any lawful"}, lawful) ==
               {:error, [{:missing_data, :alignment_requirement}]}

      # ... while the normalised shape the data layer produces is checked
      assert check(ruleset, %{"alignment" => %{require: ["lawful"]}}, lawful) == :ok
    end
  end

  # `feats` is the only key in the schema whose answer depends on **whose** block
  # asked, and it is measured rather than reasoned (Dan, 14.08.2026,
  # `GAME_CHECKS.md` H7): «фит с вещи не позволит взять другой фит, требующий тот
  # фит, который мы взяли с вещи… Но вот КЛАСС можно взять».
  describe "feats — one key, two answers" do
    # The same block, the same build, the same worn feat: only `requirement_of`
    # differs, and the answers are opposite. Both in one test on purpose — either
    # one alone passes under a model that gets the other wrong.
    test "the same worn feat opens a class and does not open a feat", %{ruleset: ruleset} do
      build = worn(Build.new(levels: [:fighter]), [:dodge])
      block = %{"feats" => ["dodge"]}

      assert Prereqs.check(block, context(build, ruleset, :class)) == []
      assert Prereqs.check(block, context(build, ruleset, :feat)) == [{:requires_feat, :dodge}]

      # …and the split is about the item alone: a slot satisfies both, so does a
      # class grant (Siala hands a Fighter `Toughness` at level 1).
      slotted = Build.new(levels: [:fighter], feats: %{1 => %{general: :dodge}})
      granted = %{"feats" => ["toughness"]}

      for kind <- [:class, :feat] do
        assert Prereqs.check(block, context(slotted, ruleset, kind)) == []
        assert Prereqs.check(granted, context(slotted, ruleset, kind)) == []
      end
    end

    # A branch of `any_of` is checked with the same context, so the split travels
    # into a disjunction instead of quietly reverting there.
    test "an any_of branch inherits the caller's side", %{ruleset: ruleset} do
      build = worn(Build.new(levels: [:wizard]), [:dodge])
      block = %{"any_of" => [%{"feats" => ["dodge"]}, %{"race" => ["dwarf"]}]}

      assert Prereqs.check(block, context(build, ruleset, :class)) == []

      assert Prereqs.check(block, context(build, ruleset, :feat)) ==
               [{:requires_any_of, [[{:requires_feat, :dodge}], [{:requires_race, [:dwarf]}]]}]
    end

    # ⚠ A context that does not say whose block it is gets neither answer. Both
    # defaults would be silent and both would be wrong somewhere: `feats_owned`
    # is a false legality for a feat, `feats_permanent` a false illegality for a
    # class. Dead code today — the two callers in the core both state it — and
    # kept as the guard that keeps it dead.
    test "a context with no side named refuses to guess", %{ruleset: ruleset} do
      build = worn(Build.new(levels: [:fighter]), [:dodge])
      nameless = build |> context(ruleset, :class) |> Map.delete(:requirement_of)

      assert Prereqs.check(%{"feats" => ["dodge"]}, nameless) ==
               [{:missing_data, {:prerequisite, :feats}}]
    end
  end

  # Второй ключ, которого вещи не закрывают, — и, в отличие от `feats` выше,
  # ответ у него ОДИН на оба блока: требования по характеристике не несёт
  # ни один из 23 классов ни на одном ruleset'е, так что второй ответ был бы
  # догадкой про требование, которого нет.
  #
  # Факт назван Dan 16.08.2026 (`GAME_CHECKS.md` S1): «статы с вещей не работают
  # при выборе фитов. Только поинт бай + левел апы, это сразу как факт». То же
  # самое стоит в источнике — «It is this unmodified score (the base score) that
  # matters when meeting the prerequisite of a feat» (`fandom:Ability score`,
  # revid 71148), — то есть правило держится на двух независимых опорах, а не
  # на одном слове.
  describe "abilities — базовое значение против того, что в листе" do
    # 🔴 Тот самый баг: до 16.08.2026 требование читало значение вместе с
    # вещами, и билд с силой 30 в листе получал фит, которого игре не отдаст.
    # Обе половины в одном тесте намеренно: «не пускает с вещами» поодиночке
    # зеленеет и на модели, которая не пускает вообще никого.
    test "надетое требование не закрывает, а базовое — закрывает", %{ruleset: ruleset} do
      block = %{"abilities" => %{"str" => 19}}
      levels = List.duplicate(:fighter, 21)

      geared =
        Build.new(
          levels: levels,
          base_abilities: abilities(%{str: 18}),
          gear: %Gear{abilities: %{str: 12}}
        )

      grown =
        Build.new(
          levels: levels,
          base_abilities: abilities(%{str: 18}),
          ability_increases: %{4 => :str}
        )

      assert check(ruleset, block, geared) == {:error, [{:requires_ability, :str, 19}]}
      assert check(ruleset, block, grown) == :ok

      # Положительный контроль: пояс настоящий и до статов доезжает — 30 в листе
      # против 18 базовых. Без него тест зеленел бы и на билде без вещей вовсе.
      stats = Rules.compute(geared, ruleset)
      assert stats.abilities.str == 30
      assert stats.abilities_naked.str == 18
    end

    # ⚠ Половина, без которой следующий читатель «починит» заодно и эффекты:
    # одна и та же вещь ОДНОВРЕМЕННО считается в числах и не выполняет
    # требование. Ретроактивность хитов при этом измерена в игре (Dan,
    # 16.08.2026, кейс G2: `+12 CON` превратили 760 хитов в 1000), и правка S1
    # её не трогает ни на единицу.
    test "тот же +12 CON даёт хиты и не даёт права на фит", %{ruleset: ruleset} do
      levels = List.duplicate(:barbarian, 21)
      fields = [levels: levels, base_abilities: abilities(%{con: 14})]
      base = Build.new(fields)
      geared = Build.new(fields ++ [gear: %Gear{abilities: %{con: 12}}])

      # Эффект: +6 к модификатору на каждом из 21 уровня.
      assert Rules.compute(geared, ruleset).hp - Rules.compute(base, ruleset).hp == 6 * 21

      # Требование: то же самое телосложение, тот же билд — и отказ не сдвинулся.
      block = %{"abilities" => %{"con" => 21}}

      assert check(ruleset, block, base) == {:error, [{:requires_ability, :con, 21}]}
      assert check(ruleset, block, geared) == {:error, [{:requires_ability, :con, 21}]}
    end

    # ⚠ Статы без базового значения — это «не смогли решить», а не «пройдено»
    # и не «возьмём одетое запасным вариантом». Молчаливый запасной вариант и
    # есть та ложная легальность, которую правка убирает, поэтому здесь стоит
    # контекст, у которого одетое значение требование бы ЗАКРЫЛО. Ветка мёртвая
    # на живых вызовах — `stats` всегда приходит из `compute/2` — и этот тест
    # держит её мёртвой.
    test "статы без базового значения — это missing_data, а не пропуск", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])
      geared_only = %{context(build, ruleset, :feat) | stats: %{abilities: %{str: 30}}}

      assert Prereqs.check(%{"abilities" => %{"str" => 13}}, geared_only) ==
               [{:missing_data, {:prerequisite, :abilities}}]
    end
  end

  # source: fandom "Resist energy" — `|prereq=[[fortitude]] save bonus +8`. The
  # page's own note settles which number is meant: "a (single-class) fighter with
  # constitution 10 cannot take this feat at level 12 (when his fortitude save
  # goes up to +8)" — the constitution is spelled out because it counts, so the
  # comparison is against the saving throw, not the base save.
  #
  # ⚠️ …но с 16.08.2026 против сейва БЕЗ ВЕЩЕЙ (`GAME_CHECKS.md` S2), то есть
  # и телосложение здесь считается голое. Раздел ниже — про это.
  #
  # ⚠️ И с 17.08.2026 против сейва НА ВХОДЕ в уровень (S6). Та же цитата,
  # прочитанная до конца: пример источника называет воина 12-го уровня, чтобы
  # сказать, что фит ему **не даётся**, — «cannot take this feat at level 12
  # (when his fortitude save goes up to +8)». Раньше мы читали из неё только
  # «телосложение считается» и на воине 12 отвечали `:ok`, то есть ровно
  # обратное тому, что предложение утверждает.
  describe "save_bonus" do
    test "compares against the saving throw, not the base save", %{ruleset: ruleset} do
      # fighter 11: base fortitude 7 (revid 71988), CON 10 -> +0
      short = Build.new(levels: List.duplicate(:fighter, 11))

      # fighter 13: base fortitude 8 уже на входе (двенадцатый её и приносит)
      long = Build.new(levels: List.duplicate(:fighter, 13))

      assert check(ruleset, %{"save_bonus" => %{"fortitude" => 8}}, short) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}

      assert check(ruleset, %{"save_bonus" => %{"fortitude" => 8}}, long) == :ok
    end

    # The same level 11 fighter with constitution 12 does qualify — which is what
    # the wiki's "with constitution 10" is there to rule out.
    test "the governing ability counts towards it", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:fighter, 11),
          base_abilities: %{str: 10, dex: 10, con: 12, int: 10, wis: 10, cha: 10}
        )

      assert check(ruleset, %{"save_bonus" => %{"fortitude" => 8}}, build) == :ok
    end

    # Ветка мёртвая на живых вызовах — снимок всегда приходит из `compute/2`, —
    # и тест держит её мёртвой. Снимок нарочно несёт `fort`, которого хватило
    # бы с запасом: молчаливый откат на одетое число и есть та ложная
    # легальность, которую правка S2 убирает, только невидимая.
    test "сейв без голого значения — это missing_data, а не пропуск", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])

      geared_only =
        Map.put(context(build, ruleset, :feat), :stats_entering_level, %{fort: 30})

      assert Prereqs.check(%{"save_bonus" => %{"fortitude" => 8}}, geared_only) ==
               [{:missing_data, {:prerequisite, :save_bonus}}]
    end

    # ⚠️ И вторая половина той же мёртвой ветки, заведённая правкой S6: снимка
    # НЕТ вовсе. Так выглядит контекст класса (`Rules.LevelUp` его не строит —
    # ни один класс ключа `save_bonus` не несёт, проверено обходом обоих
    # ruleset'ов) и любой вызывающий, забывший снимок. Ответ громкий, а не
    # «пройдено» и не откат на `stats` рядом, где число больше.
    test "требование по сейву без снимка на входе — это missing_data", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 20))
      without = context(build, ruleset, :class)

      refute Map.has_key?(without, :stats_entering_level)

      assert Prereqs.check(%{"save_bonus" => %{"fortitude" => 8}}, without) ==
               [{:missing_data, {:prerequisite, :save_bonus}}]
    end

    test "all three saves are addressable, and unmet ones are reported together", %{
      ruleset: ruleset
    } do
      # ⚠️ Воин 20, а не 12: с правкой S6 у двенадцатого не закрыта и Стойкость
      # (8 приезжает ровно на этом уровне), и тест перестал бы показывать
      # разницу между закрытым требованием и незакрытыми. У двадцатого на входе
      # Стойкость 11, а Реакция и Воля по 6 — то есть закрыто ровно одно из трёх.
      build = Build.new(levels: List.duplicate(:fighter, 20))

      assert check(
               ruleset,
               %{"save_bonus" => %{"fortitude" => 8, "reflex" => 8, "will" => 8}},
               build
             ) ==
               {:error, [{:requires_save_bonus, :ref, 8}, {:requires_save_bonus, :will, 8}]}
    end

    test "a save outside the vocabulary is named rather than ignored", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 20))

      assert check(ruleset, %{"save_bonus" => %{"luck" => 8}}, build) ==
               {:error, [{:missing_data, {:prerequisite, :save_bonus}}]}
    end
  end

  # Третий ключ, которого вещи не закрывают, — соседний с `abilities` выше и
  # доигранный до конца в тот же день (Dan, 16.08.2026, `GAME_CHECKS.md` S2):
  #
  #   > «вещи на спасы также не откроют фит, должен быть закрыт».
  #
  # ⚠️ Цитаты источника здесь нет, только слово владельца, и в этом отличие
  # от S1: там за правилом стоят и замер, и строка Fandom. Помечено честно —
  # `source: user`.
  #
  # ⚠️ Фит с ключом `save_bonus` ровно один на оба ruleset'а — `Resist energy`,
  # — поэтому блок требований здесь синтетический: он проверяет ПРАВИЛО, а не
  # одну запись данных, и переживёт её переписывание шардом.
  describe "save_bonus — голый сейв против того, что в листе" do
    # 🔴 Тот самый баг: до 16.08.2026 воин 11 со Стойкостью 7 надевал вещи
    # «+20 к сейвам» и получал фит, которого игра не даст. Обе половины в одном
    # тесте намеренно: «не пускает с вещами» поодиночке зеленеет и на модели,
    # которая не пускает вообще никого.
    test "надетое требование не закрывает, а заработанное — закрывает", %{ruleset: ruleset} do
      block = %{"save_bonus" => %{"fortitude" => 8}}
      levels = List.duplicate(:fighter, 11)

      geared = Build.new(levels: levels, gear: %Gear{saves: 20})

      # То же требование, закрытое своим: +1 за каждые 5 рангов Spellcraft.
      #
      # ⚠️ Ранги куплены на 10-м, а не на 11-м, и это не косметика: с правкой
      # S6 требование смотрит на состояние ВХОДА в уровень, а купленное на самом
      # уровне в него не входит. Отдельный тест ниже проверяет именно это.
      earned = Build.new(levels: levels, skills: %{10 => %{spellcraft: 5}})

      assert check(ruleset, block, geared) == {:error, [{:requires_save_bonus, :fort, 8}]}
      assert check(ruleset, block, earned) == :ok

      # Положительный контроль: вещи настоящие и до числа доезжают — 27 в панели
      # против 7 голых. Без него тест зеленел бы и на билде без вещей вовсе.
      stats = Rules.compute(geared, ruleset)
      assert stats.fort == 27
      assert stats.saves_naked.fort == 7
    end

    # ⚠️ Половина, без которой следующий читатель «починит» заодно и эффекты:
    # одна и та же вещь ОДНОВРЕМЕННО считается в числах и не выполняет
    # требование. Та же граница, что у S1 и у замера H7: вещь отвечает
    # на «сколько» и на «можно ли» по-разному.
    test "те же +20 к сейвам дают сейвы и не дают права на фит", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 11)
      base = Build.new(levels: levels)
      geared = Build.new(levels: levels, gear: %Gear{saves: 20})

      # Эффект: все три сейва выросли ровно на 20.
      for save <- [:fort, :ref, :will] do
        assert Map.fetch!(Rules.compute(geared, ruleset), save) -
                 Map.fetch!(Rules.compute(base, ruleset), save) == 20
      end

      # Требование: тот же билд, та же вещь — и отказ не сдвинулся.
      block = %{"save_bonus" => %{"fortitude" => 8}}

      assert check(ruleset, block, base) == {:error, [{:requires_save_bonus, :fort, 8}]}
      assert check(ruleset, block, geared) == {:error, [{:requires_save_bonus, :fort, 8}]}
    end

    # ⚠️ Вторая дорога вещи к сейву, и без неё правка S1 обходилась бы задней
    # дверью: `+12 CON` там требования по характеристике уже не выполняет,
    # а здесь выполнял бы через Стойкость — те же вещи, тот же фит, другой ключ.
    test "модификатор с вещей до требования тоже не доезжает", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 11)
      belt = Build.new(levels: levels, gear: %Gear{abilities: %{con: 12}})

      # То же телосложение, но купленное поинт-баем, — требование закрывает.
      bought = Build.new(levels: levels, base_abilities: abilities(%{con: 12}))

      block = %{"save_bonus" => %{"fortitude" => 8}}

      assert Rules.compute(belt, ruleset).fort == 13
      assert check(ruleset, block, belt) == {:error, [{:requires_save_bonus, :fort, 8}]}
      assert check(ruleset, block, bought) == :ok
    end

    # ⚠️ Третья дорога: фит, одолженный вещью. H7 уже говорит, что такой фит
    # не открывает ДРУГОЙ фит по имени; здесь он не открывает его и числом,
    # что то же самое правило, а не второе похожее. Тот же фит из слота —
    # открывает: слот снять нельзя.
    test "фит с вещи требование не закрывает, а тот же фит из слота — закрывает", %{
      ruleset: ruleset
    } do
      levels = List.duplicate(:fighter, 11)
      amulet = Build.new(levels: levels, gear: %Gear{feats: [:great_fortitude]})
      slot = Build.new(levels: levels, feats: %{1 => %{{:general, 1} => :great_fortitude}})

      block = %{"save_bonus" => %{"fortitude" => 8}}

      # Оба несут фит и оба получают его +2 в число — расходится только право.
      assert Rules.compute(amulet, ruleset).fort == 9
      assert Rules.compute(slot, ruleset).fort == 9

      assert check(ruleset, block, amulet) == {:error, [{:requires_save_bonus, :fort, 8}]}
      assert check(ruleset, block, slot) == :ok
    end

    # 🔴 Половина, без которой правка ушла бы в другую крайность — в ложную
    # НЕлегальность. Всё, что билд заработал сам, требование выполнять обязано:
    # ранги Spellcraft, фит из слота, классовое умение в форме фита.
    test "своё требование выполняет: Spellcraft, фит и классовое умение", %{ruleset: ruleset} do
      block = %{"save_bonus" => %{"fortitude" => 8}}

      # ⚠️ Ранги на 10-м: с правкой S6 купленное на самом уровне в требование
      # не входит, а здесь проверяется другое — что Spellcraft вообще считается.
      spellcraft =
        Build.new(levels: List.duplicate(:fighter, 11), skills: %{10 => %{spellcraft: 5}})

      feat =
        Build.new(
          levels: List.duplicate(:fighter, 11),
          feats: %{1 => %{{:general, 1} => :great_fortitude}}
        )

      # Divine grace паладина: на Сиале выдаётся с 4-го уровня класса, харизма
      # 18 даёт +4 ко всем трём (`siala_41/classes.json` → feat_level_shift).
      paladin = fn cha ->
        Build.new(levels: List.duplicate(:paladin, 9), base_abilities: abilities(%{cha: cha}))
      end

      assert check(ruleset, block, spellcraft) == :ok
      assert check(ruleset, block, feat) == :ok
      assert check(ruleset, block, paladin.(18)) == :ok

      # ⚠️ Отрицательный контроль к последнему: базовой прогрессии паладина
      # (Стойкость 6 на девятом) на требование НЕ хватает — то есть `:ok` выше
      # держится именно на классовом умении, а не на самом классе.
      assert check(ruleset, block, paladin.(10)) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}
    end

    # Разметка сейвов и Spellcraft лежат в общих файлах, поэтому правило обязано
    # вести себя одинаково на обоих ruleset'ах — фит-то ванильный.
    test "ответ одинаков на обоих ruleset'ах" do
      block = %{"save_bonus" => %{"fortitude" => 8}}
      levels = List.duplicate(:fighter, 11)
      geared = Build.new(levels: levels, gear: %Gear{saves: 20})
      earned = Build.new(levels: levels, skills: %{10 => %{spellcraft: 5}})

      for version <- Data.versions() do
        ruleset = Data.ruleset!(version)

        assert check(ruleset, block, geared) == {:error, [{:requires_save_bonus, :fort, 8}]},
               version

        assert check(ruleset, block, earned) == :ok, version
      end
    end
  end

  # Четвёртая дверь, и первая, которую закрыл не блок «Вещи», а сам источник
  # (`GAME_CHECKS.md` S3, 17.08.2026). `fandom:Resist energy` (revid 63837),
  # Notes:
  #
  #   > «The fortitude bonus from ''[[luck of heroes]]'' does not count towards
  #   > the fortitude required».
  #
  # Замер Dan подтвердил строку на Сиале дословно:
  #
  #   > «Проверил, на 9 уровне со взятым luck of heroes фит Resist energy был
  #   > не доступен. На 12 уже доступен».
  #
  # ⚠️ Здесь, в отличие от блоков выше, требование НЕ синтетическое: проверяется
  # настоящий `resist_energy` из данных — потому что и замер был про него, и
  # числа сходятся только с его собственным порогом. Правило же (признак на
  # записи прибавки) проверяется соседним тестом на синтетическом блоке.
  describe "save_bonus — прибавка, исключённая источником из требования" do
    # Воин, телосложение 12, `Luck of heroes` общим слотом 1-го уровня
    # (`max_character_level: 1` — на других уровнях его не взять вовсе).
    defp with_luck(n) do
      Build.new(
        levels: List.duplicate(:fighter, n),
        base_abilities: abilities(%{con: 12}),
        feats: %{1 => %{{:general, 1} => :luck_of_heroes}}
      )
    end

    # 🔴 Оба числа замера в одном тесте. На 9-м Удача и есть то единственное
    # очко, на котором всё держится: в листе ровно 8 при требовании 8 — и фита
    # в игре нет. На 12-м базовой Стойкости хватает без неё, и фит есть; без
    # этой второй половины «не пускаем» зеленело бы и на модели, не пускающей
    # никого.
    test "воин 9 с Удачей фит не получает, воин 12 — получает", %{ruleset: ruleset} do
      assert Rules.validate_feat(with_luck(9), :resist_energy, ruleset) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}

      assert Rules.validate_feat(with_luck(12), :resist_energy, ruleset) == :ok

      # Положительный контроль: в листе на 9-м стоит ровно требуемое число,
      # то есть отказ держится на исключении, а не на нехватке сейва вообще.
      assert Rules.compute(with_luck(9), ruleset).fort == 8
    end

    # 🔴 Та же граница, что у S1 и S2: требование и эффект — разные вопросы,
    # и один источник отвечает на них по-разному. Без этой половины следующий
    # читатель «доделает» правку до вычитания прибавки из самого сейва.
    test "та же Удача даёт +1 ко всем трём сейвам и не даёт права на фит", %{ruleset: ruleset} do
      plain =
        Build.new(levels: List.duplicate(:fighter, 9), base_abilities: abilities(%{con: 12}))

      for save <- [:fort, :ref, :will] do
        assert Map.fetch!(Rules.compute(with_luck(9), ruleset), save) -
                 Map.fetch!(Rules.compute(plain, ruleset), save) == 1
      end

      assert Rules.validate_feat(with_luck(9), :resist_energy, ruleset) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}
    end

    # 🔴 Положительный контроль на прибавке той же формы и той же величины
    # стороны капа: `Great fortitude` — тоже фит, тоже плоский, тоже поверх
    # капа, — и он требование ЗАКРЫВАЕТ. Без этого правка неотличима от
    # «прибавки фитов в требование не идут», то есть от ложной нелегальности
    # на тринадцати записях вместо ложной легальности на одной.
    test "другой фит той же формы требование закрывает", %{ruleset: ruleset} do
      block = %{"save_bonus" => %{"fortitude" => 8}}
      levels = List.duplicate(:fighter, 9)

      luck = with_luck(9)

      great =
        Build.new(
          levels: levels,
          base_abilities: abilities(%{con: 12}),
          feats: %{1 => %{{:general, 1} => :great_fortitude}}
        )

      assert check(ruleset, block, luck) == {:error, [{:requires_save_bonus, :fort, 8}]}
      assert check(ruleset, block, great) == :ok
    end

    # ⚠️ И на расовой склонности, которая даёт ТО ЖЕ САМОЕ (+1 на все три,
    # `flat`, поверх капа) и от которой Удачу не отличить ничем, кроме признака
    # в данных. Гоблин (Halfling, CLAUDE.md §4) с телосложением 12 требование
    # закрывает — то есть признак читается с записи, а не с формы прибавки.
    test "расовая склонность Lucky требование закрывает", %{ruleset: ruleset} do
      goblin =
        Build.new(
          levels: List.duplicate(:fighter, 9),
          base_abilities: abilities(%{con: 12}),
          race: :halfling
        )

      assert check(ruleset, %{"save_bonus" => %{"fortitude" => 8}}, goblin) == :ok
    end

    # Сиала про это правило не высказывалась ни словом, значит действует ваниль
    # (CLAUDE.md §3) — но за ним стоит замер, сделанный НА САМОЙ Сиале.
    test "ответ одинаков на обоих ruleset'ах" do
      for version <- Data.versions() do
        ruleset = Data.ruleset!(version)

        assert Rules.validate_feat(with_luck(9), :resist_energy, ruleset) ==
                 {:error, [{:requires_save_bonus, :fort, 8}]},
               version

        assert Rules.validate_feat(with_luck(12), :resist_energy, ruleset) == :ok, version
      end
    end
  end

  # Пятая дверь и последняя из трёх правок по одному ключу (`GAME_CHECKS.md` S6,
  # 17.08.2026). Та же страница, третья строка тех же `Notes`:
  #
  #   > «The prerequisite for this feat must be met **before leveling up**. For
  #   > example, a (single-class) fighter with constitution 10 cannot take this
  #   > feat at level 12 (when his fortitude save goes up to +8), but can at any
  #   > level after this on which he gains a feat».
  #
  # 🔴 Замер Dan — четыре билда, и четвёртый РАЗЛИЧАЮЩИЙ: первые три одинаково
  # хорошо объясняла и вторая гипотеза («требование на самом деле 9»). Воин 9
  # с телосложением 14 её убил — он входит в уровень и выходит из него
  # с восемью, и фит в игре есть; при требовании 9 его бы не было.
  #
  # ⚠️ И с того же дня — уточнение S7b: снимок это НЕ весь взятый уровень
  # долой. Из уровня в требование не попадает ровно одно, базовая прогрессия
  # сейва, а прибавка характеристики этого уровня считается. Тесты ниже держат
  # обе половины разом: без второй правка отказывает воину, которому игра фит
  # даёт (ложная нелегальность), без первой — предлагает тому, кому не даёт.
  describe "save_bonus — сейв на входе в уровень" do
    # Воин без единого фита на сейвы: телосложение и базовая прогрессия, и всё.
    defp plain_fighter(n, con) do
      Build.new(levels: List.duplicate(:fighter, n), base_abilities: abilities(%{con: con}))
    end

    # 🔴 Все четыре наблюдения замера, одной таблицей и в одном тесте. Порознь
    # любая строка зеленеет и на неверной модели: «не пускает» — на модели,
    # не пускающей никого, «пускает» — на прежней, пускавшей лишнего.
    #
    # ⚠️ Четвёртая строка тут не для симметрии: именно она отличает «считаем
    # состояние до уровня» от «требование равно 9». Уберёшь — и обе модели
    # снова станут неразличимы, как были до 17.08.2026.
    test "четыре билда замера: лист один и тот же, право разное", %{ruleset: ruleset} do
      luck = fn n ->
        Build.new(
          levels: List.duplicate(:fighter, n),
          base_abilities: abilities(%{con: 12}),
          feats: %{1 => %{{:general, 1} => :luck_of_heroes}}
        )
      end

      refused = {:error, [{:requires_save_bonus, :fort, 8}]}

      # вход 7 (Удача в требование не идёт, S3), лист 8 — в игре фита нет
      assert Rules.validate_feat(luck.(9), :resist_energy, ruleset) == refused
      # вход 8, лист 10 — есть
      assert Rules.validate_feat(luck.(12), :resist_energy, ruleset) == :ok
      # вход 7, лист 8 — нет. 🔴 До правки здесь стояло `:ok`.
      assert Rules.validate_feat(plain_fighter(12, 10), :resist_energy, ruleset) == refused
      # вход 8, лист 8 — есть. Различающая строка.
      assert Rules.validate_feat(plain_fighter(9, 14), :resist_energy, ruleset) == :ok

      # Положительный контроль: в листе у третьего и четвёртого стоит ОДНО
      # И ТО ЖЕ число, а ответы разные — то есть решает именно момент, а не
      # величина.
      assert Rules.compute(plain_fighter(12, 10), ruleset).fort == 8
      assert Rules.compute(plain_fighter(9, 14), ruleset).fort == 8
    end

    # ⚠️ Правило про МОМЕНТ, а не про число: у воина 12 с телосложением 10 фита
    # нет, у воина 13 с тем же телосложением — есть, хотя Стойкость у них
    # одинаковая. Ровно это и говорит источник своим «but can at any level
    # after this on which he gains a feat».
    test "тот же сейв на следующем уровне требование закрывает", %{ruleset: ruleset} do
      block = %{"save_bonus" => %{"fortitude" => 8}}

      assert Rules.compute(plain_fighter(12, 10), ruleset).fort ==
               Rules.compute(plain_fighter(13, 10), ruleset).fort

      assert check(ruleset, block, plain_fighter(12, 10)) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}

      assert check(ruleset, block, plain_fighter(13, 10)) == :ok
    end

    # 🔴 Слот не всегда на последнем уровне билда: открытый чужой билд правят
    # с середины лестницы. Момент берётся от уровня, на котором тратится слот,
    # а не от того, докуда билд в итоге дорос, — иначе воин 41 получал бы фит
    # на любом уровне, начиная с первого.
    test "слот в середине лестницы меряется своим уровнем, а не концом билда", %{
      ruleset: ruleset
    } do
      long = plain_fighter(41, 10)

      assert Rules.validate_feat(long, %{feat: :resist_energy, at: 12}, ruleset) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}

      assert Rules.validate_feat(long, %{feat: :resist_energy, at: 13}, ruleset) == :ok
      assert Rules.validate_feat(long, %{feat: :resist_energy, at: 41}, ruleset) == :ok
    end

    # 🔴 Главный риск правки, под тестом: общий механизм «всё считать до уровня»
    # сломал бы КАЖДЫЙ эпический фит на 21-м уровне — персонаж входил бы в него
    # двадцатым. Замерено, что этого не происходит (Dan, 17.08.2026): «насчет
    # эпик фита на 21 — он доступен сразу, проверил на 21 уровне рейнджера».
    test "эпические фиты на 21-м уровне по-прежнему доступны", %{ruleset: ruleset} do
      ranger =
        Build.new(
          levels: List.duplicate(:ranger, 21),
          base_abilities: abilities(%{str: 18, dex: 18, con: 14, wis: 14})
        )

      for feat <- [:epic_prowess, :epic_toughness, :great_strength, :epic_fortitude] do
        assert Rules.validate_feat(ranger, feat, ruleset) == :ok, inspect(feat)
      end

      # Отрицательный контроль: на 20-м их нет вовсе, то есть `:ok` выше держится
      # на 21-м уровне персонажа, а не на том, что требование не проверяется.
      twentieth = %{ranger | levels: List.duplicate(:ranger, 20)}

      for feat <- [:epic_prowess, :epic_toughness, :great_strength, :epic_fortitude] do
        assert Rules.validate_feat(twentieth, feat, ruleset) ==
                 {:error, [{:requires_character_level, 21}]},
               inspect(feat)
      end
    end

    # 🔴 Сторож против «унификации»: два соседних ключа читают состояние ПОСЛЕ
    # взятия уровня, и это ЗАМЕРЕНО, а не «про них ничего не сказано».
    # Соблазн свести все ключи к одному моменту велик ровно потому, что три
    # правки подряд легли на `save_bonus`; здесь стоит цена такой унификации.
    #
    #   * `abilities` — S9, Dan 17.08.2026: «взял 13 силу ровно на 12 уровне,
    #     сразу после фит power attack был доступен для выбора». Этим ключом
    #     гейтятся 39 фитов из 310, то есть ошибка была бы самой массовой
    #     из возможных;
    #   * `base_attack_bonus` — S7, тот же день: «на 8 уровне на добавочном фите
    #     воина improved critical доступен». БАБ +8 приезжает ровно на 8-м.
    #
    # ⚠️ У обоих отрицательный контроль обязателен: без него `:ok` держался бы
    # хоть на непроверяемом требовании.
    test "abilities и base_attack_bonus читают состояние ПОСЛЕ уровня", %{ruleset: ruleset} do
      # Сила 12 на входе в 12-й, 13 после прибавки — `Power attack` требует 13
      # и больше ничего, поэтому он и выбран замером.
      strong =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{str: 12}),
          ability_increases: %{12 => :str}
        )

      assert Rules.validate_feat(strong, :power_attack, ruleset) == :ok

      assert Rules.validate_feat(%{strong | ability_increases: %{}}, :power_attack, ruleset) ==
               {:error, [{:requires_ability, :str, 13}]}

      # БАБ: на 7-м у воина 7, на 8-м — 8, и требование закрывается ровно тем
      # уровнем, на котором тратится слот. Характеристики не трогаем вовсе:
      # `Improved critical` ни одной не требует.
      eighth = Build.new(levels: List.duplicate(:fighter, 8))
      seventh = %{eighth | levels: List.duplicate(:fighter, 7)}

      assert Rules.compute(seventh, ruleset).base_attack == 7
      assert Rules.compute(eighth, ruleset).base_attack == 8

      assert Rules.validate_feat(eighth, :improved_critical, ruleset) == :ok

      assert Rules.validate_feat(seventh, :improved_critical, ruleset) ==
               {:error, [{:requires_bab, 8}]}
    end

    # 🔴 Уточнение S7b, замер Dan 17.08.2026: «на 12 уровне взял CON +1 → с 11
    # до 12. Resist energy был доступен». Вход в 12-й: база 7 + модификатор 0
    # (телосложение 11) = 7 при требовании 8 — то есть игра засчитала прибавку
    # ЭТОГО уровня и получила 7 + 1 = 8.
    #
    # ⚠️ Контроль у этого наблюдения снят другим билдом и стоит в тесте выше:
    # воин 12 с телосложением 10 (S6) даёт тот же снимок 7 и тот же модификатор
    # 0, и фита в игре нет. Разница между двумя билдами ровно одна — прибавка.
    # Поэтому здесь тот же билд ещё и без неё: порознь любая половина зеленеет
    # и на неверной модели.
    test "прибавка характеристики этого уровня в снимок ВХОДИТ", %{ruleset: ruleset} do
      taken =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{con: 11}),
          ability_increases: %{12 => :con}
        )

      assert Rules.validate_feat(taken, :resist_energy, ruleset) == :ok

      # 🔴 До правки 17.08.2026 здесь стоял отказ: снимок выбрасывал взятый
      # уровень целиком и уносил прибавку вместе с прогрессией сейва.
      refused = {:error, [{:requires_save_bonus, :fort, 8}]}

      assert Rules.validate_feat(%{taken | ability_increases: %{}}, :resist_energy, ruleset) ==
               refused

      # …и прибавка считается ТА, а не любая: та же единица, вложенная в силу,
      # Стойкости не даёт ничего. Без этой строки тест зеленел бы и на модели
      # «есть прибавка на уровне — засчитать уровень целиком».
      assert Rules.validate_feat(
               %{taken | ability_increases: %{12 => :str}},
               :resist_energy,
               ruleset
             ) ==
               refused
    end

    # ⚠️ Прибавка взятого уровня перекладывается ВНУТРЬ снимка, и переложить её
    # надо так, чтобы не затереть чужую. Сегодня прибавки идут раз в четыре
    # уровня и столкнуться не могут — но это правило ДАННЫХ, а не ядра
    # (CLAUDE.md §3), и билд с прибавками на соседних уровнях собирается руками
    # уже сейчас. При затирании телосложение осталось бы 11, модификатор 0,
    # и фит был бы отбит — тихая ложная нелегальность ровно того вида, который
    # эта задача убирает.
    test "прибавка соседнего уровня при этом не теряется", %{ruleset: ruleset} do
      consecutive =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{con: 10}),
          ability_increases: %{11 => :con, 12 => :con}
        )

      # Обе прибавки доехали: 10 + 1 + 1 = 12, то есть модификатор +1.
      assert Rules.compute(consecutive, ruleset).abilities.con == 12
      assert Rules.validate_feat(consecutive, :resist_energy, ruleset) == :ok

      # Отрицательный контроль: с ОДНОЙ прибавкой телосложение 11, модификатор
      # 0 — и фита нет. Значит `:ok` выше держится на том, что в снимке обе.
      assert Rules.validate_feat(
               %{consecutive | ability_increases: %{12 => :con}},
               :resist_energy,
               ruleset
             ) == {:error, [{:requires_save_bonus, :fort, 8}]}
    end

    # 🔴 И вторая половина того же уточнения, замеренная отдельно (S7c): ранги
    # навыка, купленные на том же уровне, НЕ считаются. «Взял 5 раз навык
    # spellcraft, но не повышал CON до 12. Как итог resist energy не доступен».
    # На Сиале Знание магии даёт +1 ко всем сейвам за каждые 5 рангов, значит
    # пятый ранг — ровно то очко, на котором держится ответ.
    #
    # ⚠️ Тест стоит здесь именно как ОПРОВЕРЖЕНИЕ обобщения, а не как «цена
    # правки»: S7b выглядел как порядок экранов мастера левелапа («считается
    # всё, что выбирается раньше фитов»), и ранги туда попадали. Не попали.
    # Правило про конкретное слагаемое, а не про порядок.
    test "ранги навыка, купленные на этом уровне, в снимок НЕ входят", %{ruleset: ruleset} do
      levels = List.duplicate(:fighter, 12)
      plain = abilities(%{con: 10})

      on_this_level =
        Build.new(
          levels: levels,
          base_abilities: plain,
          skills: %{11 => %{spellcraft: 4}, 12 => %{spellcraft: 1}}
        )

      a_level_earlier =
        Build.new(levels: levels, base_abilities: plain, skills: %{11 => %{spellcraft: 5}})

      # Стойкость в листе у обоих одна и та же — расходится только момент
      # покупки пятого ранга.
      assert Rules.compute(on_this_level, ruleset).fort ==
               Rules.compute(a_level_earlier, ruleset).fort

      assert Rules.validate_feat(on_this_level, :resist_energy, ruleset) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}

      assert Rules.validate_feat(a_level_earlier, :resist_energy, ruleset) == :ok
    end

    # 🔴 Три правила по сейву кусают ОДНОВРЕМЕННО, и ни одно не отменяет
    # остальных. Воин 12 с телосложением 10: вещи `+20` (S2), `Luck of heroes`
    # (S3) и восьмёрка, приехавшая ровно на этом уровне (S6). В панели у него
    # Стойкость 29 при требовании 8 — и фита нет.
    test "все три правила по сейву держатся вместе", %{ruleset: ruleset} do
      stacked =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{con: 10}),
          feats: %{1 => %{{:general, 1} => :luck_of_heroes}},
          gear: %Gear{saves: 20}
        )

      stats = Rules.compute(stacked, ruleset)
      assert stats.fort == 29
      assert stats.saves_naked.fort == 9
      assert stats.saves_for_prereqs.fort == 8

      assert Rules.validate_feat(stacked, :resist_energy, ruleset) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}

      # …и снимаются они тоже по одному: тот же билд уровнем позже проходит,
      # потому что на входе в 13-й у него уже 8 своих.
      thirteenth = %{stacked | levels: List.duplicate(:fighter, 13)}
      assert Rules.validate_feat(thirteenth, :resist_energy, ruleset) == :ok
    end

    # 🔴 Четвёртое уточнение — ПОВЕРХ трёх, а не вместо них, и вот один билд,
    # на котором видно все четыре сразу. Воин 12, телосложение 11, поднятое
    # на 12-м: вещи `+20` не считаются (S2), `Luck of heroes` не считается (S3),
    # базовая прогрессия этого уровня не считается (S6) — а прибавка
    # характеристики этого же уровня считается (S7b), и она-то и переводит
    # 7 в 8. В панели у него Стойкость 30 при требовании 8, и всё, на чём
    # держится ответ, — та единственная единица.
    test "четвёртое уточнение ложится поверх трёх, а не вместо них", %{ruleset: ruleset} do
      stacked =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{con: 11}),
          ability_increases: %{12 => :con},
          feats: %{1 => %{{:general, 1} => :luck_of_heroes}},
          gear: %Gear{saves: 20}
        )

      stats = Rules.compute(stacked, ruleset)
      assert stats.fort == 30
      assert stats.saves_naked.fort == 10
      assert stats.saves_for_prereqs.fort == 9

      assert Rules.validate_feat(stacked, :resist_energy, ruleset) == :ok

      # Отрицательный контроль на том же билде: убрать одну прибавку — и три
      # оставшихся правила отбивают фит, хотя вещей и Удачи меньше не стало.
      # То есть `:ok` выше держится на прибавке, а не на том, что вещи или
      # Удача где-то просочились.
      assert Rules.validate_feat(%{stacked | ability_increases: %{}}, :resist_energy, ruleset) ==
               {:error, [{:requires_save_bonus, :fort, 8}]}
    end

    # Сиала про это правило не высказывалась ни словом, значит действует ваниль
    # (CLAUDE.md §3) — но замер сделан НА САМОЙ Сиале.
    #
    # ⚠️ Все пять точек замеров разом: правило живёт в ядре, а числа, на которых
    # оно кусает, — в данных (таблица сейвов воина, прибавка от Знания магии,
    # признак у `Luck of heroes`), и лежат они в каждом ruleset'е своими файлами.
    # Значит одинаковый ответ здесь — это проверка, а не тавтология.
    test "ответ одинаков на обоих ruleset'ах" do
      refused = {:error, [{:requires_save_bonus, :fort, 8}]}

      raised =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{con: 11}),
          ability_increases: %{12 => :con}
        )

      ranks =
        Build.new(
          levels: List.duplicate(:fighter, 12),
          base_abilities: abilities(%{con: 10}),
          skills: %{11 => %{spellcraft: 4}, 12 => %{spellcraft: 1}}
        )

      luck =
        Build.new(
          levels: List.duplicate(:fighter, 9),
          base_abilities: abilities(%{con: 12}),
          feats: %{1 => %{{:general, 1} => :luck_of_heroes}}
        )

      for version <- Data.versions() do
        ruleset = Data.ruleset!(version)

        # S6: базовая прогрессия взятого уровня в требование не идёт
        assert Rules.validate_feat(plain_fighter(12, 10), :resist_energy, ruleset) == refused,
               version

        # S6, различающая точка: вошёл в уровень уже с восемью
        assert Rules.validate_feat(plain_fighter(9, 14), :resist_energy, ruleset) == :ok, version

        # S7b: прибавка характеристики этого уровня — идёт
        assert Rules.validate_feat(raised, :resist_energy, ruleset) == :ok, version

        # S7c: ранги, купленные на этом уровне, — не идут
        assert Rules.validate_feat(ranks, :resist_energy, ruleset) == refused, version

        # S3: `Luck of heroes` — не идёт
        assert Rules.validate_feat(luck, :resist_energy, ruleset) == refused, version
      end
    end
  end

  # source: fandom "Epic skill focus" — "21st level, 20 ranks in the chosen
  # skill". The skill is chosen when the feat is taken, so the requirement is on
  # *some* skill; naming one would be inventing which.
  describe "any_skill_ranks" do
    test "any single skill at the rank satisfies it", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:rogue, 21),
          skills: %{21 => %{discipline: 20}}
        )

      assert check(ruleset, %{"any_skill_ranks" => 20}, build) == :ok
    end

    test "ranks spread across skills do not add up", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:rogue, 21),
          skills: %{21 => %{discipline: 15, tumble: 15}}
        )

      assert check(ruleset, %{"any_skill_ranks" => 20}, build) ==
               {:error, [{:requires_any_skill_ranks, 20}]}
    end

    # Ranks bought level by level are the same ranks.
    test "ranks accumulate across levels", %{ruleset: ruleset} do
      build =
        Build.new(
          levels: List.duplicate(:rogue, 21),
          skills: %{5 => %{discipline: 8}, 21 => %{discipline: 12}}
        )

      assert check(ruleset, %{"any_skill_ranks" => 20}, build) == :ok
    end
  end

  # «21st level, 20 ranks in **the chosen skill**» (`epic_skill_focus`), and the
  # emphasis is the rule. Дан подтвердил 02.08.2026: фит берётся один раз на
  # навык и требование именно про него.
  #
  # A requirement block cannot point at a pick, so the parser can only write
  # `any_skill_ranks: 20`. That leaves a one-directional hole — the feat is
  # legal on a skill with no ranks whenever *some other* skill has twenty — and
  # this is where it is closed: at the pick, where the choice is.
  describe "any_skill_ranks bound to the chosen skill" do
    setup do
      build =
        Build.new(
          levels: List.duplicate(:rogue, 21),
          skills: %{21 => %{discipline: 20, tumble: 4}}
        )

      %{build: build, prereqs: %{"any_skill_ranks" => 20}}
    end

    test "the chosen skill's own ranks are what count", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, repeatable: takes(:skill), choice: :discipline) == :ok
    end

    # The hole, closed: twenty ranks of Discipline used to buy the feat for
    # Tumble, which has four.
    test "another skill's ranks no longer buy it", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, repeatable: takes(:skill), choice: :tumble) ==
               {:error, [{:requires_chosen_skill_ranks, :tumble, 20}]}
    end

    # ⚠️ Половина контракта, которая ждёт данных. Пока пик не назвал навык,
    # сверять не с чем, и билд не имеет права стать нелегальным по правилу,
    # которого ещё нет.
    test "with no choice recorded the check is exactly what it was", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, repeatable: takes(:skill)) == :ok
      assert check(ruleset, prereqs, build) == :ok
    end

    # Связь рисуется через СЛОВАРЬ, в который резолвится домен, а не через имя
    # домена в коде: параметр из другого словаря навыком не становится.
    test "a parameter that is not a skill leaves the check unbound", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build,
               repeatable: takes(:spell_school),
               choice: :evocation
             ) == :ok
    end

    test "and a feat that takes no parameter at all is untouched", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, choice: :tumble) == :ok
    end
  end

  # Три ключа, заведённые задачей 3.104 под `fandom:Skill focus` (Notes).
  # Здесь они проверяются на СИНТЕТИЧЕСКОМ фите — то есть как поведение
  # интерпретатора, — а на настоящем `Skill focus` со всеми четырьмя ключами
  # разом их держит `Data.FeatRequirementsTest`.
  describe "chosen_skill_ranks_if_trained_only — порог включает свойство навыка" do
    setup do
      %{
        build: Build.new(levels: List.duplicate(:rogue, 9), skills: %{9 => %{listen: 4}}),
        prereqs: %{"chosen_skill_ranks_if_trained_only" => 1}
      }
    end

    # ⚠️ `tumble` требует тренировки, `listen` — нет, и билд один и тот же:
    # разница ровно в свойстве выбранного навыка. Ни одного имени навыка
    # в `Rules.Prereqs` при этом нет — признак читается из словаря ruleset'а.
    test "навык с тренировкой и без — один билд, разные ответы", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert Map.fetch!(ruleset.skills, :tumble).trained_only?
      refute Map.fetch!(ruleset.skills, :listen).trained_only?

      assert check(ruleset, prereqs, build, repeatable: takes(:skill), choice: :tumble) ==
               {:error, [{:requires_chosen_skill_ranks, :tumble, 1}]}

      assert check(ruleset, prereqs, build, repeatable: takes(:skill), choice: :listen) == :ok
    end

    test "купленный ранг требование закрывает", %{ruleset: ruleset, prereqs: prereqs} do
      one = Build.new(levels: List.duplicate(:rogue, 9), skills: %{9 => %{tumble: 1}})

      assert check(ruleset, prereqs, one, repeatable: takes(:skill), choice: :tumble) == :ok
    end

    # Та же половина контракта, что у соседнего `any_skill_ranks`: значения нет
    # — сравнивать не с чем, и билд не имеет права стать нелегальным.
    test "без записанного значения проверка молчит", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, repeatable: takes(:skill)) == :ok
      assert check(ruleset, prereqs, build) == :ok
    end

    # Тот же довод, что у `any_skill_ranks`: связь рисуется через СЛОВАРЬ,
    # в который резолвится домен. Параметр не из словаря навыков навыком
    # не становится, и молчаливо не срабатывающий ключ был бы ложной
    # легальностью, которую никто не увидит.
    test "параметр не из словаря навыков ключ не включает", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build,
               repeatable: takes(:spell_school),
               choice: :evocation
             ) == :ok
    end
  end

  describe "class_levels_for_skill — требование к СОСТАВУ БИЛДА, включённое выбором" do
    setup do
      %{prereqs: %{"class_levels_for_skill" => %{"perform" => %{"bard" => 1}}}}
    end

    # 🔴 То, ради чего ключ отдельный от `only_on_class_levels_for_skill`:
    # уровень, на котором тратится слот, здесь НИ ПРИ ЧЁМ. Соседний ключ
    # ответил бы «только на уровне барда» и сделал бы законный пик ложно
    # нелегальным.
    test "бард-воин проходит на ВОИНСКОМ уровне, а чистый воин — нет", %{
      ruleset: ruleset,
      prereqs: prereqs
    } do
      bard_fighter = Build.new(levels: [:bard | List.duplicate(:fighter, 8)])
      fighter = Build.new(levels: List.duplicate(:fighter, 9))

      assert Build.class_at(bard_fighter, 9) == :fighter

      assert check(ruleset, prereqs, bard_fighter, repeatable: takes(:skill), choice: :perform) ==
               :ok

      assert check(ruleset, prereqs, fighter, repeatable: takes(:skill), choice: :perform) ==
               {:error, [{:requires_class_level, :bard, 1}]}
    end

    # Навык вне таблицы правила не несёт вовсе — иначе ключ запретил бы фит
    # на всех остальных значениях.
    test "навык вне таблицы не задет", %{ruleset: ruleset, prereqs: prereqs} do
      fighter = Build.new(levels: List.duplicate(:fighter, 9))

      assert check(ruleset, prereqs, fighter, repeatable: takes(:skill), choice: :discipline) ==
               :ok
    end

    test "без записанного значения проверка молчит", %{ruleset: ruleset, prereqs: prereqs} do
      fighter = Build.new(levels: List.duplicate(:fighter, 9))

      assert check(ruleset, prereqs, fighter, repeatable: takes(:skill)) == :ok
    end

    # Значение объявлено и нечитаемо — требование существует и не проверено,
    # значит названо, а не пропущено. Та же линия, что у всех остальных
    # ключей этого модуля.
    test "нечитаемое значение называется, а не пропускается", %{ruleset: ruleset} do
      fighter = Build.new(levels: List.duplicate(:fighter, 9))
      broken = %{"class_levels_for_skill" => %{"perform" => "bard"}}

      assert check(ruleset, broken, fighter, repeatable: takes(:skill), choice: :perform) ==
               {:error, [{:missing_data, {:prerequisite, :class_levels_for_skill}}]}
    end
  end

  describe "no_feat_variant_for_skills — пары не существует" do
    setup do
      %{
        build: Build.new(levels: List.duplicate(:fighter, 9)),
        prereqs: %{"no_feat_variant_for_skills" => ["ride"]}
      }
    end

    # ⚠️ Форма отказа та же, что у словаря выбора, и это не экономия на формах:
    # «такого варианта фита нет» — ровно то, что говорит `{:invalid_choice, …}`.
    # Требовательная форма («не хватает X») позвала бы игрока дотягивать
    # то, чего не бывает.
    test "названное значение отбивается формой словаря выбора, соседнее — нет", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, repeatable: takes(:skill), choice: :ride) ==
               {:error, [{:invalid_choice, @feat, :ride}]}

      assert check(ruleset, prereqs, build, repeatable: takes(:skill), choice: :discipline) == :ok
    end

    test "без записанного значения проверка молчит", %{
      ruleset: ruleset,
      build: build,
      prereqs: prereqs
    } do
      assert check(ruleset, prereqs, build, repeatable: takes(:skill)) == :ok
    end
  end

  # CLAUDE.md §9 / HANDOFF: the point of the key is that a feat with a
  # refinement the schema cannot express becomes **available with a caveat**
  # instead of unavailable. Before it existed the whole phrase went to
  # `unparsed`, nothing was checked, and the feat was refused.
  describe "qualifiers" do
    test "the readable half is checked and the refinement does not refuse", %{ruleset: ruleset} do
      prereqs = %{
        "feats" => ["spell_focus"],
        "qualifiers" => ["in the chosen spell school"]
      }

      without = Build.new(levels: List.duplicate(:wizard, 10))
      with_feat = %{without | feats: %{1 => %{general: :spell_focus}}}

      assert check(ruleset, prereqs, without) == {:error, [{:requires_feat, :spell_focus}]}
      assert check(ruleset, prereqs, with_feat) == :ok
    end

    test "the refinement is declared unmodelled rather than dropped", %{ruleset: ruleset} do
      prereqs = %{
        "feats" => ["spell_focus"],
        "qualifiers" => ["in the chosen spell school", "(6x per day)"]
      }

      ruleset = with_prereqs(ruleset, prereqs)

      assert BuildCalculator.Rules.Prereqs.qualifiers(ruleset.feats[@feat]) == [
               {:not_modelled, {:feat_qualifier, @feat, "in the chosen spell school"}},
               {:not_modelled, {:feat_qualifier, @feat, "(6x per day)"}}
             ]
    end

    # And it reaches the build's own gap list, so a player who took the feat is
    # told what was not checked.
    test "a taken feat's refinement shows up in stats.gaps", %{ruleset: ruleset} do
      ruleset =
        with_prereqs(ruleset, %{
          "feats" => ["spell_focus"],
          "qualifiers" => ["in the chosen spell school"]
        })

      build =
        Build.new(levels: List.duplicate(:wizard, 10), feats: %{3 => %{general: @feat}})

      assert {:not_modelled, {:feat_qualifier, @feat, "in the chosen spell school"}} in Rules.compute(
               build,
               ruleset
             ).gaps
    end

    test "a feat with no qualifiers reports none", %{ruleset: ruleset} do
      ruleset = with_prereqs(ruleset, %{"character_level" => 1})

      assert BuildCalculator.Rules.Prereqs.qualifiers(ruleset.feats[@feat]) == []
      assert BuildCalculator.Rules.Prereqs.qualifiers(nil) == []
    end
  end

  # Ключ, которым оговорка выше перестаёт быть оговоркой там, где её есть чем
  # проверить.
  #
  # source: Dan, 17.08.2026, дословно: «по поводу arcane archer: требование эльф
  # или темный эльф, т.е. оба подходят, и weapon focus на одно из 4 орудий:
  # короткий лук/арбалет, длинный лук, тяжелый арбалет».
  # source: `siala:Тайный лучник`, revid 20405 — «Умения: Владение оружием
  # (Короткий лук, Длинный лук, Малый арбалет или Большой арбалет)».
  #
  # ⚠️ Таблица гоняется на СИНТЕТИЧЕСКОМ фите, а не на Тайном лучнике: здесь
  # проверяется правило, а не запись данных. За саму запись отвечает
  # `Data.ClassRequirementsTest` и прогон ниже по настоящему классу.
  describe "feat_choices — требование к значению, с которым взят фит" do
    @choices %{"weapon_focus" => ["shortbow", "longbow", "light_crossbow", "heavy_crossbow"]}

    defp with_focus(choice) do
      build = Build.new(levels: List.duplicate(:fighter, 8))

      case choice do
        :none -> build
        weapon -> Build.put_feat(build, 3, :general, :weapon_focus, weapon)
      end
    end

    # Одной таблицей, потому что все пять строк — один и тот же вопрос с разными
    # ответами, и поодиночке каждая зеленеет на сломанной модели: «лук проходит»
    # верно и там, где не проверяется ничего, а «меч не проходит» — там, где
    # не проходит никто.
    test "значение сверяется со списком, а незаписанное молчит", %{ruleset: ruleset} do
      refusal =
        {:requires_feat_choice, :weapon_focus,
         [:shortbow, :longbow, :light_crossbow, :heavy_crossbow]}

      table = [
        # {что записано у weapon_focus, чего ждём}
        {:longbow, []},
        {:shortbow, []},
        # 🔴 Строка, ради которой правка и делалась: ваниль знает только два
        # лука, Сиала добавила оба арбалета.
        {:heavy_crossbow, []},
        {:light_crossbow, []},
        {:longsword, [refusal]},
        # Фит взят, значение не записано (ссылка старше задачи 3.26 либо фит
        # объявлен с вещи): сравнивать не с чем, значит молчим — раздел моддока
        # про то, почему отказ здесь был бы ложной нелегальностью.
        {nil, []},
        # Фита нет вовсе — этот ключ молчит, потому что про фит говорит соседний
        # `feats`. Иначе игрок получил бы две причины про одно.
        {:none, []}
      ]

      for {choice, expected} <- table do
        assert Prereqs.check(
                 %{"feat_choices" => @choices},
                 context(with_focus(choice), ruleset, :class)
               ) ==
                 expected,
               "выбор #{inspect(choice)}"
      end
    end

    # Второе взятие того же фита — законное (`distinct?: true`), и годится
    # ЛЮБОЕ из записанных значений: требование говорит «есть ли у тебя фокус
    # на луке», а не «на что взят последний».
    test "хватает одного подходящего значения из нескольких", %{ruleset: ruleset} do
      build =
        Build.new(levels: List.duplicate(:fighter, 8))
        |> Build.put_feat(3, :general, :weapon_focus, :longsword)
        |> Build.put_feat(6, :general, :weapon_focus, :longbow)

      assert Prereqs.check(%{"feat_choices" => @choices}, context(build, ruleset, :class)) == []
    end

    # Обе причины сразу, а не одна: у билда нет ни фита, ни значения. Проверка
    # порядка тоже здесь — «нужен фит» обязано стоять раньше «нужен фит на лук».
    test "рядом с `feats` даёт ровно одну причину, и первой", %{ruleset: ruleset} do
      block = %{"feats" => ["weapon_focus"], "feat_choices" => @choices}

      assert Prereqs.check(block, context(with_focus(:none), ruleset, :class)) ==
               [{:requires_feat, :weapon_focus}]

      assert Prereqs.check(block, context(with_focus(:longsword), ruleset, :class)) ==
               [
                 {:requires_feat_choice, :weapon_focus,
                  [:shortbow, :longbow, :light_crossbow, :heavy_crossbow]}
               ]
    end

    # Кривое значение называется, а не пропускается: требование настоящее, и
    # молчание про него — та же дыра, что у любого нечитаемого ключа здесь.
    test "нечитаемый список даёт missing_data", %{ruleset: ruleset} do
      block = %{"feat_choices" => %{"weapon_focus" => "longbow"}}

      assert Prereqs.check(block, context(with_focus(:longbow), ruleset, :class)) ==
               [{:missing_data, {:prerequisite, :feat_choices}}]
    end

    # Ключ признан интерпретатором, значит загрузчик не выкинет его из блока
    # класса (`@requirement_keys` собирается из `Prereqs.keys/0`).
    test "ключ входит в список признаваемых" do
      assert :feat_choices in Prereqs.keys()
    end

    # 🔴 Задача 3.99. Здесь стояло, что ключ `requirement_of` не читает вовсе,
    # и довод был записан в моддоке: «у вещи значения нет ни в каком случае».
    # Задача 3.97 это сняла — объявление под «Вещами» теперь несёт значение, —
    # и молчаливое чтение только слотов означало бы, что `Weapon Focus
    # (Longbow)` с вещи открывает Мастера оружия без единой проверки.
    #
    # ⚠️ Линия ровно та же, что у соседнего ключа `feats`, и проведена тем же
    # `requirement_of`: КЛАСС значение с вещи видит (замер H7), ФИТ — нет.
    test "значение с вещи видит класс и не видит фит", %{ruleset: ruleset} do
      worn =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          gear: %Gear{feats: [{:weapon_focus, :longbow}]}
        )

      assert Prereqs.check(%{"feat_choices" => @choices}, context(worn, ruleset, :class)) == []

      refusal =
        {:requires_feat_choice, :weapon_focus,
         [:shortbow, :longbow, :light_crossbow, :heavy_crossbow]}

      # ⚠️ У ФИТА тот же билд молчит, а не отказывает, и это не полумера:
      # значения с вещи он не видит ВОВСЕ, то есть сравнивать не с чем — та же
      # политика «не записано — молчим». Отказ ему приходит соседним ключом
      # `feats`, который вещь у фита не засчитывает (H7); печатать здесь вторую
      # причину про то же самое значило бы обвинить дважды.
      assert Prereqs.check(%{"feat_choices" => @choices}, context(worn, ruleset, :feat)) == []

      assert Prereqs.check(
               %{"feats" => ["weapon_focus"], "feat_choices" => @choices},
               context(worn, ruleset, :feat)
             ) == [{:requires_feat, :weapon_focus}]

      # Положительный контроль: значение с вещи НЕ ТО — класс отказывает, то
      # есть гировый маршрут действительно проверяется, а не проходит всегда.
      wrong =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          gear: %Gear{feats: [{:weapon_focus, :longsword}]}
        )

      assert Prereqs.check(%{"feat_choices" => @choices}, context(wrong, ruleset, :class)) ==
               [refusal]
    end
  end

  # 🔴 Задача 3.99, разряд 2. «[[weapon focus]] in a [[melee weapon]]» —
  # требование к значению, названное СВОЙСТВОМ, а не списком. До правки оно
  # стояло непроверяемой оговоркой, и `Weapon Focus (Longbow)` открывал
  # и Мастера оружия, и Чемпиона Торма — ложная легальность.
  describe "feat_choice_properties — требование к свойству выбранного значения" do
    @melee %{"weapon_focus" => %{"ranged" => false}}

    test "свойство сверяется со справочником, а незаписанное молчит", %{ruleset: ruleset} do
      refusal = {:requires_feat_choice_property, :weapon_focus, :ranged, false}

      table = [
        {:longsword, []},
        {:club, []},
        # Метательное — дальнобойное по данным Fandom (`ranged: true` у всех
        # четырёх), значит Мастера оружия оно не открывает. Следствие данных,
        # и оно названо здесь, а не оставлено молчаливым.
        {:throwing_axe, [refusal]},
        {:longbow, [refusal]},
        {:sling, [refusal]},
        # Взял, не записал какое — сравнивать не с чем (та же политика, что
        # у `feat_choices`).
        {nil, []},
        {:none, []}
      ]

      for {choice, expected} <- table do
        assert Prereqs.check(
                 %{"feat_choice_properties" => @melee},
                 context(with_focus(choice), ruleset, :class)
               ) == expected,
               "выбор #{inspect(choice)}"
      end
    end

    # Дизъюнкция по ВЗЯТИЯМ: хватает одного ближнего фокуса, даже если рядом
    # взят лук. «Weapon focus in a melee weapon» спрашивает «есть ли такой», а
    # не «на что взят последний».
    test "хватает одного взятия с подходящим свойством", %{ruleset: ruleset} do
      build =
        Build.new(levels: List.duplicate(:fighter, 8))
        |> Build.put_feat(3, :general, :weapon_focus, :longbow)
        |> Build.put_feat(6, :general, :weapon_focus, :longsword)

      assert Prereqs.check(
               %{"feat_choice_properties" => @melee},
               context(build, ruleset, :class)
             ) == []
    end

    # Свойство, которого ядро прочитать не умеет, — требование настоящее
    # и непроверенное: называем громко, а не совпадаем молча с `nil`.
    test "неизвестное свойство даёт missing_data", %{ruleset: ruleset} do
      block = %{"feat_choice_properties" => %{"weapon_focus" => %{"shiny" => true}}}

      assert Prereqs.check(block, context(with_focus(:longsword), ruleset, :class)) ==
               [{:missing_data, {:prerequisite, :feat_choice_properties}}]
    end

    test "ключ входит в список признаваемых" do
      assert :feat_choice_properties in Prereqs.keys()
    end

    # Прогон по НАСТОЯЩИМ записям: правило одно на оба ruleset'а, потому что
    # `ranged` заполнено у всех 47 записей справочника в обоих.
    test "оба класса требуют ближнего фокуса на обоих ruleset'ах", %{ruleset: ruleset} do
      for rs <- [ruleset, Data.ruleset!("vanilla")],
          class <- [:weapon_master, :champion_of_torm] do
        assert %{"weapon_focus" => %{"ranged" => false}} =
                 rs.classes[class].requirements[:feat_choice_properties]
      end
    end
  end

  # 🔴 Задача 3.99, разряд 2, вторая половина: «proficiency with the chosen
  # weapon» у `Weapon focus` и `Improved critical`.
  describe "proficiency_with_chosen_weapon — владение выбранным оружием" do
    @proficiency %{"proficiency_with_chosen_weapon" => true}

    test "три ответа справочника, и отказывает только один", %{ruleset: ruleset} do
      table = [
        # Группа названа, фита нет — отказ.
        {:scimitar, [{:requires_feat, :siala_blade_proficiency}]},
        {:longbow, [{:requires_feat, :siala_ranged_proficiency}]},
        # Владения не требует вовсе — это ОТВЕТ, а не пропуск (замер Dan
        # 16.08.2026 про дубину, посох и рукопашный удар).
        {:club, []},
        {:unarmed_strike, []},
        # Владения не назвал никто: отказать нечем. Билд говорит об этом сам —
        # `Rules.FeatChoices.gaps/3`.
        {:creature_weapon, []},
        # Значение не записано — сравнивать не с чем.
        {nil, []},
        {:none, []}
      ]

      for {choice, expected} <- table do
        assert Prereqs.check(@proficiency, feat_context(with_focus(choice), ruleset, choice)) ==
                 expected,
               "выбор #{inspect(choice)}"
      end
    end

    # Положительный контроль: с владением тот же выбор проходит. Ложная
    # нелегальность здесь была бы хуже исходного дефекта.
    test "с владением выбор законен", %{ruleset: ruleset} do
      armed =
        Build.new(levels: List.duplicate(:fighter, 8))
        |> Build.put_feat(1, :general, :siala_blade_proficiency)
        |> Build.put_feat(3, :general, :weapon_focus, :scimitar)

      assert Prereqs.check(@proficiency, feat_context(armed, ruleset, :scimitar)) == []
    end

    # 🔴 Фит с вещи требование ФИТА не выполняет (H7), а требование КЛАССА —
    # выполняет. Один ключ, два ответа, и линию проводит `requirement_of`.
    #
    # ⚠️ Это не спорит с тем, что то же владение с вещи позволяет взять оружие
    # В РУКИ (`Rules.GearWeapon`): там эффект, здесь пререквизит.
    test "владение с вещи открывает класс и не открывает фит", %{ruleset: ruleset} do
      worn =
        Build.new(
          levels: List.duplicate(:fighter, 8),
          gear: %Gear{feats: [{:siala_blade_proficiency, nil}]}
        )
        |> Build.put_feat(3, :general, :weapon_focus, :scimitar)

      assert Prereqs.check(@proficiency, feat_context(worn, ruleset, :scimitar)) ==
               [{:requires_feat, :siala_blade_proficiency}]

      assert Prereqs.check(@proficiency, %{
               feat_context(worn, ruleset, :scimitar)
               | requirement_of: :class
             }) == []
    end

    # Оружие, которого в справочнике нет вовсе: требование настоящее
    # и непроверенное — называем громко.
    test "неизвестное оружие даёт missing_data", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 8))

      assert Prereqs.check(@proficiency, feat_context(build, ruleset, :no_such_weapon)) ==
               [{:missing_data, {:prerequisite, :proficiency_with_chosen_weapon}}]
    end

    test "ключ входит в список признаваемых" do
      assert :proficiency_with_chosen_weapon in Prereqs.keys()
    end
  end

  # The three keys of the contract, checked against the real dictionary rather
  # than a fixture — this is the pair of halves meeting. Each of these feats used
  # to be refused with `{:missing_data, {:feat_prerequisites, id}}` because its
  # whole prose went to `unparsed`; "на вики есть требование, но мы его не
  # учитываем" is what Дан was seeing in the interface.
  describe "the new keys, on the feats they were written for" do
    test "resist_energy is gated on a fortitude save and nothing else", %{ruleset: ruleset} do
      assert ruleset.feats[:resist_energy].prereqs == %{"save_bonus" => %{"fortitude" => 8}}

      # fighter 11, CON 10 -> fortitude 7
      refute :ok ==
               Rules.validate_feat(
                 Build.new(levels: List.duplicate(:fighter, 11)),
                 :resist_energy,
                 ruleset
               )

      # 🔴 Здесь стоял воин 12 с `:ok` — и это была ложная легальность,
      # найденная замером S6 (17.08.2026). Восьмёрка приезжает у него ровно
      # НА двенадцатом уровне, а требование сравнивается с тем, с чем он в этот
      # уровень вошёл. Воин 13 — первый, у кого 8 было уже на входе.
      assert Rules.validate_feat(
               Build.new(levels: List.duplicate(:fighter, 12)),
               :resist_energy,
               ruleset
             ) == {:error, [{:requires_save_bonus, :fort, 8}]}

      assert Rules.validate_feat(
               Build.new(levels: List.duplicate(:fighter, 13)),
               :resist_energy,
               ruleset
             ) == :ok
    end

    test "epic_skill_focus asks for 20 ranks in some skill", %{ruleset: ruleset} do
      bare = Build.new(levels: List.duplicate(:rogue, 21))
      trained = %{bare | skills: %{21 => %{discipline: 20}}}

      assert Rules.validate_feat(bare, :epic_skill_focus, ruleset) ==
               {:error, [{:requires_any_skill_ranks, 20}]}

      assert Rules.validate_feat(trained, :epic_skill_focus, ruleset) == :ok
    end

    # ⚠️ ЗДЕСЬ СТОЯЛО «weapon_focus is available, with its refinement declared»,
    # и оно было верно до задачи 3.99: фраза «proficiency with the chosen
    # weapon» была оговоркой, потому что оружие в модели не называлось. Теперь
    # это ПРОВЕРЯЕМОЕ требование (`proficiency_with_chosen_weapon`), и тест
    # проверяет ровно смену состояния: оговорки нет, отказ есть.
    #
    # ⚠️ Отказ виден только там, где выбор ЗАПИСАН: без значения сравнивать
    # не с чем, и молчание здесь — та же политика, что у `feat_choices`.
    test "weapon_focus asks for proficiency instead of declaring it unchecked", %{
      ruleset: ruleset
    } do
      build = Build.new(levels: List.duplicate(:fighter, 12))

      assert Rules.feat_caveats(:weapon_focus, ruleset) == []
      assert Rules.validate_feat(build, :weapon_focus, ruleset) == :ok

      assert Rules.validate_feat(build, %{feat: :weapon_focus, choice: :scimitar}, ruleset) ==
               {:error, [{:requires_feat, :siala_blade_proficiency}]}

      armed = Build.put_feat(build, 1, :general, :siala_blade_proficiency)

      assert Rules.validate_feat(armed, %{feat: :weapon_focus, choice: :scimitar}, ruleset) == :ok

      # ⚠️ И третий ответ справочника: владения не требует вовсе — это ответ,
      # а не пропуск (замер Dan 16.08.2026 про дубину, посох и рукопашный удар).
      assert Rules.validate_feat(build, %{feat: :weapon_focus, choice: :club}, ruleset) == :ok
    end

    # ⚠ The invariant that matters, held over the whole dictionary rather than
    # over one feat: **nothing may be silently legal**. A refinement that reaches
    # neither a refusal nor a caveat would leave the calculator more confident
    # and less right than when the phrase still sat in `unparsed`.
    test "no feat with a refinement is legal and silent about it", %{ruleset: ruleset} do
      with_qualifiers =
        for {id, feat} <- ruleset.feats,
            is_map(feat.prereqs),
            Map.has_key?(feat.prereqs, "qualifiers"),
            do: id

      # Было 12, стало 10, после задачи 3.5 — 8, после 3.99 — 3 на Сиале.
      # Уменьшение законно ровно в одном случае: оговорка не исчезла, а стала
      # ПРОВЕРЯЕМЫМ ПРАВИЛОМ. Падение без такого переезда означало бы, что
      # оговорку потеряли, и билд стал бы «легальным» молча.
      #
      # ⚠️ Инвариант тут не число, а вторая половина теста: НИ ОДИН фит
      # с оговоркой в блоке не молчит. Число же держится отдельно и по именам —
      # `Rules.PrereqsTest`, «оговорка снимается только проверкой».
      assert length(with_qualifiers) >= 3

      # ⚠️ У инварианта появилось РОВНО ОДНО законное исключение (задача 3.99),
      # и оно названо предикатом ядра, а не списком id: фраза, которую
      # `same_choice_as` рядом действительно сравнивает, — не дырка, а правило.
      # Список id здесь протух бы в первый же день, когда шард объявит ещё один
      # фит повторяемым.
      silent =
        for id <- with_qualifiers,
            Rules.feat_caveats(id, ruleset) == [],
            not FeatChoices.same_choice_enforced?(ruleset.feats[id]),
            do: id

      assert silent == []

      # Положительный контроль: исключение не проглатывает всё подряд — фиты,
      # у которых ключа нет, по-прежнему обязаны говорить.
      loud =
        for id <- with_qualifiers,
            not FeatChoices.same_choice_enforced?(ruleset.feats[id]),
            do: id

      assert loud != []
    end

    # 🔴 Задача 3.99, разряд 1. Оговорка «тот же выбор» печаталась и там, где
    # `same_choice_as` рядом её УЖЕ проверяет: ключ читается только у
    # повторяемых фитов, а повторяемость — свойство ruleset'а, и парсер решить
    # за оба не может.
    test "оговорка «тот же выбор» снимается ровно там, где ключ работает", %{ruleset: ruleset} do
      vanilla = Data.ruleset!("vanilla")

      # На Сиале три фита повторяемы, значит выбор сравнивается — и молчим.
      for id <- [:arcane_defense, :epic_weapon_focus, :epic_weapon_specialization] do
        assert Rules.feat_caveats(id, ruleset) == [], "#{id}: оговорка про проверенное"
        refute is_nil(ruleset.feats[id].repeatable[:choice])
      end

      # В ванили те же три НЕ повторяемы, ключ не срабатывает — и оговорка
      # обязана стоять. Один и тот же файл данных, разные ответы.
      assert Rules.feat_caveats(:epic_weapon_focus, vanilla) == [
               {:not_modelled, {:feat_qualifier, :epic_weapon_focus, "with the chosen weapon"}}
             ]

      assert is_nil(vanilla.feats[:epic_weapon_focus].repeatable)

      # 🔴 И зеркало того же дефекта: у `epic_spell_focus` парсер фразу
      # из `qualifiers` УБРАЛ (`supersedes`), а в ванили ключ не срабатывает —
      # то есть требование не проверялось и об этом не говорилось. Фраза
      # восстанавливается из `same_choice_quote`, со снятой разметкой.
      assert Rules.feat_caveats(:epic_spell_focus, vanilla) == [
               {:not_modelled, {:feat_qualifier, :epic_spell_focus, "in the chosen school"}}
             ]

      assert Rules.feat_caveats(:epic_spell_focus, ruleset) == []

      # Положительный контроль: фит, у которого ключ работает на ОБОИХ, молчит
      # на обоих — то есть тест видит разницу, а не сам ruleset.
      for rs <- [ruleset, vanilla] do
        assert Rules.feat_caveats(:weapon_specialization, rs) == []
      end
    end

    # The same for classes: three blocks carry a refinement, and a class card
    # that showed nothing would have the identical problem. Champion of Torm and
    # Weapon Master both want «Weapon focus» *in a melee weapon* — the feat is
    # checked, the weapon is not, because weapons are not modelled.
    test "a class refinement is reachable too", %{ruleset: ruleset} do
      # ⚠️ Здесь стояло «Champion of Torm and Weapon Master both want «Weapon
      # focus» *in a melee weapon* — the feat is checked, the weapon is not,
      # because weapons are not modelled». Задача 3.99 это сняла: оружие
      # моделируется с 3.5, и «in a melee weapon» стало требованием
      # (`feat_choice_properties`). У Чемпиона Торма оговорок не осталось вовсе.
      assert Rules.class_caveats(:champion_of_torm, ruleset) == []

      # ⚠️ А здесь стоял ЧЕСТНЫЙ остаток Мастера оружия — «unarmed strike is
      # excluded from the prerequisites», второе исключение его страницы,
      # которое 3.99 выразить было нечем. Задача 3.107 его выразила
      # (`feat_choice_excludes`, перечисление), и оговорка ушла вместе
      # с правилом: печатать «не проверяем» про проверенное — та самая ложная
      # неопределённость наоборот (CLAUDE.md §6).
      assert Rules.class_caveats(:weapon_master, ruleset) == []

      # The third is vanilla's Purple Dragon Knight. Under `siala_41` it has
      # none, because the shard **restates** the whole block on its own page
      # rather than adding to it (the same rule as for feats) — so the caveat is
      # gone along with the requirement it refined.
      assert Rules.class_caveats(:purple_dragon_knight, Data.ruleset!("vanilla")) == [
               {:not_modelled, {:class_qualifier, :purple_dragon_knight, "(requires ride 1)"}}
             ]

      assert Rules.class_caveats(:purple_dragon_knight, ruleset) == []
      assert Rules.class_caveats(:fighter, ruleset) == []
    end
  end

  describe "prose the parser could not read" do
    # Same contract as a prestige class whose block is prose: never silently
    # legal. The interface may soften this to "не проверено"; the core does not.
    test "a feat with prose and no structure is refused", %{ruleset: ruleset} do
      build = Build.new(levels: List.duplicate(:fighter, 20))

      assert check(ruleset, nil, build, prereq_raw: "spellcaster level 3+") ==
               {:error, [{:missing_data, {:feat_prerequisites, @feat}}]}
    end

    test "the wiki saying «none» is not prose", %{ruleset: ruleset} do
      build = Build.new(levels: [:fighter])

      for raw <- [nil, "none", "None", "-", "n/a"] do
        assert check(ruleset, nil, build, prereq_raw: raw) == :ok, "prereq_raw #{inspect(raw)}"
      end
    end

    # A partly-read block is checked on the part that was read, and still says
    # that something was not.
    test "leftover fragments are reported beside the checked keys", %{ruleset: ruleset} do
      prereqs = %{"character_level" => 21, "unparsed" => ["ability to cast 9th level spells"]}
      build = Build.new(levels: List.duplicate(:wizard, 21))

      assert check(ruleset, prereqs, build) ==
               {:error, [{:missing_data, {:feat_prerequisites, @feat}}]}

      early = Build.new(levels: List.duplicate(:wizard, 20))

      assert check(ruleset, prereqs, early) ==
               {:error,
                [
                  {:requires_character_level, 21},
                  {:missing_data, {:feat_prerequisites, @feat}}
                ]}
    end
  end

  describe "entry point" do
    test "a feat that is not in the dictionary is its own reason", %{ruleset: ruleset} do
      assert Rules.validate_feat(Build.new(), :no_such_feat, ruleset) ==
               {:error, [{:unknown_feat, :no_such_feat}]}
    end

    test "the atom form and the map form agree", %{ruleset: ruleset} do
      ruleset = with_prereqs(ruleset, %{"character_level" => 2})
      build = Build.new(levels: [:fighter, :fighter])

      assert Rules.validate_feat(build, @feat, ruleset) == :ok
      assert Rules.validate_feat(build, %{feat: @feat}, ruleset) == :ok
      assert Rules.validate_feat(build, %{feat: @feat, at: 2}, ruleset) == :ok

      assert Rules.validate_feat(build, %{feat: @feat, at: 1}, ruleset) ==
               {:error, [{:requires_character_level, 2}]}
    end
  end
end
