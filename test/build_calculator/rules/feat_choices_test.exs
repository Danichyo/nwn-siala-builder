defmodule BuildCalculator.Rules.FeatChoicesTest do
  @moduledoc """
  Feats taken **with** something, and taken again for something else.

  Feat records and choice dictionaries are built by hand here. That is not
  convenience: `repeatable` and `creature_types.json` are being written right now
  by the data role, and a test pinned to them would be measuring somebody else's
  work in progress rather than the rule. The names used are deliberately
  fictional (`:fixture_domain`, `:alpha`) — if the rule ever depended on a real
  creature type or school being spelled a particular way, these tests would not
  pass, and that is the point (CLAUDE.md §3).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatChoices, Gear, GearFeats}

  @feat :fixture_repeatable
  @plain :fixture_plain
  @derived :fixture_derived
  @counter :fixture_counter

  setup_all do
    %{ruleset: Data.ruleset!("siala_41")}
  end

  # A feat record with only the fields this path reads, in the shape the loader
  # produces. `prereqs` carries string keys because that is what `mix wiki.parse`
  # writes and the loader hands over untouched.
  defp feat(id, fields) do
    Map.merge(
      %{
        id: id,
        name: "Fixture #{id}",
        type: "general",
        epic?: false,
        bonus_for: MapSet.new(),
        available_to: MapSet.new(),
        prereq_raw: nil,
        prereqs: nil,
        unlocks: [],
        repeatable: nil,
        source: nil
      },
      Map.new(fields)
    )
  end

  defp repeatable(choice, opts) do
    %{
      choice: choice,
      distinct?: Keyword.get(opts, :distinct?, true),
      distinct_stated?: true,
      max_takes: Keyword.get(opts, :max_takes),
      quote: nil,
      source: nil,
      status: Keyword.get(opts, :status)
    }
  end

  # Повторяемость без параметра, как её кладёт загрузчик из `"choice": null`.
  # `distinct?` — `nil`: различаться нечему, и булево здесь читалось бы как
  # ответ на вопрос, которого никто не задавал.
  defp counter(opts) do
    %{
      choice: nil,
      distinct?: nil,
      distinct_stated?: false,
      max_takes: Keyword.get(opts, :max_takes),
      quote: nil,
      source: nil,
      status: Keyword.get(opts, :status)
    }
  end

  # A ruleset carrying the two fixture feats and one dictionary. `flags` is the
  # per-feat gate a dictionary file carries — `ooze` is `favored_enemy: false` in
  # the real file, and this is that mechanism with the names changed.
  defp fixture(ruleset, opts \\ []) do
    domain = Keyword.get(opts, :domain, :fixture_domain)

    domains =
      case Keyword.get(opts, :values, [:alpha, :beta, :gamma]) do
        nil ->
          %{domain => %{values: nil, flags: %{}, source: nil}}

        values ->
          %{
            domain => %{
              values: MapSet.new(values),
              flags: Keyword.get(opts, :flags, %{}),
              source: :file
            }
          }
      end

    feats =
      ruleset.feats
      |> Map.put(@feat, feat(@feat, repeatable: repeatable(domain, opts)))
      |> Map.put(@plain, feat(@plain, []))
      |> Map.put(
        @derived,
        feat(@derived,
          repeatable: repeatable(domain, opts),
          prereqs: %{
            "feats" => [Atom.to_string(@feat)],
            "same_choice_as" => [Atom.to_string(@feat)]
          }
        )
      )
      |> Map.put(@counter, feat(@counter, repeatable: counter(opts)))

    ruleset
    |> Map.put(:feats, feats)
    |> Map.put(:choice_domains, Keyword.get(opts, :domains, domains))
  end

  defp build(feats \\ %{}) do
    Build.new(levels: List.duplicate(:ranger, 10), feats: feats)
  end

  # Прикрыт ли фит побочно: его выбор обязан совпасть с выбором другого фита, а
  # тот сам отгорожен воротами — значит невыбираемое значение до него не дойдёт.
  # Один уровень, не транзитивно: этого хватает для сегодняшней цепочки и
  # честнее, чем рекурсия, которая делала бы вид, что проверено больше.
  defp covered_by_same_choice?(feat, dictionary, gate) do
    required =
      case feat.prereqs do
        %{} = p -> List.wrap(p["same_choice_as"] || p[:same_choice_as] || [])
        _none -> []
      end

    Enum.any?(required, fn id ->
      key = if is_atom(id), do: id, else: String.to_existing_atom(id)
      Map.has_key?(dictionary.flags, key) or Map.has_key?(dictionary.flags, gate)
    end)
  end

  describe "a slot may carry the choice, and both forms read alike" do
    test "the feat id is the answer either way" do
      bare = build(%{1 => %{general: :toughness}})
      with_choice = build(%{1 => %{general: {:toughness, :alpha}}})

      assert Build.feats_at(bare, 1) == [:toughness]
      assert Build.feats_at(with_choice, 1) == [:toughness]
      assert Build.feats_taken(bare, 1) == Build.feats_taken(with_choice, 1)

      assert Build.feat_id(:toughness) == :toughness
      assert Build.feat_id({:toughness, :alpha}) == :toughness
      assert Build.feat_choice(:toughness) == nil
      assert Build.feat_choice({:toughness, :alpha}) == :alpha
    end

    # The old shape is not merely *supported*, it is what a choiceless pick still
    # produces — so a build made today is byte for byte the build it would have
    # been, and every shared link, export and saved row keeps reading.
    test "a pick with no choice stores the bare id, exactly as before" do
      stored = Build.put_feat(build(), 1, :general, :toughness)

      assert stored.feats == %{1 => %{general: :toughness}}
      assert Build.feat_pick(stored, 1, :general) == :toughness
    end

    test "a pick with a choice stores the pair" do
      stored = Build.put_feat(build(), 1, :general, :favored_enemy, :alpha)

      assert stored.feats == %{1 => %{general: {:favored_enemy, :alpha}}}
      assert Build.feat_pick(stored, 1, :general) == {:favored_enemy, :alpha}
    end

    # Дан, 02.08.2026: minor, greater and epic focus in one school is the point
    # of the family. The pair is the unique key, never the choice on its own.
    test "choices are counted per feat id, not across feats" do
      taken =
        build()
        |> Build.put_feat(1, :general, :spell_focus, :alpha)
        |> Build.put_feat(3, :general, :greater_spell_focus, :alpha)

      assert Build.feat_choices(taken, :spell_focus, 10) == [:alpha]
      assert Build.feat_choices(taken, :greater_spell_focus, 10) == [:alpha]
      assert Build.feat_choices(taken, :epic_spell_focus, 10) == []
    end

    test "picks are listed with their level, slot and choice" do
      taken =
        build()
        |> Build.put_feat(1, :general, :spell_focus, :alpha)
        |> Build.put_feat(3, {:class_bonus, :ranger}, :toughness)

      assert Build.feat_picks(taken, 10) == [
               {1, :general, :spell_focus, :alpha},
               {3, {:class_bonus, :ranger}, :toughness, nil}
             ]

      assert Build.feat_picks(taken, 2) == [{1, :general, :spell_focus, :alpha}]
    end
  end

  describe "repeatability comes from the data, never from a list in the code" do
    test "a feat with no repeatable block is taken once", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: @plain}})

      assert Rules.validate_feat_pick(build(), %{feat: @plain, at: 3}, ruleset) == :ok

      assert Rules.validate_feat_pick(taken, %{feat: @plain, at: 3}, ruleset) ==
               {:error, [{:already_taken, @plain}]}
    end

    test "the same feat with the block is taken again for another value", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(taken, %{feat: @feat, choice: :beta, at: 3}, ruleset) == :ok
    end

    test "but not twice for the same value", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(taken, %{feat: @feat, choice: :alpha, at: 3}, ruleset) ==
               {:error, [{:choice_already_taken, @feat, :alpha}]}
    end

    # `Epic energy resistance` reads «may be taken multiple times, to a maximum of
    # 100 resistance to each damage type» — the same value again, on purpose. The
    # default must be overridable by data, or that feat is modelled wrong.
    test "a block that says the picks need not differ allows the repeat", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, distinct?: false)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(taken, %{feat: @feat, choice: :alpha, at: 3}, ruleset) ==
               :ok
    end

    test "a repeatable feat picked with nothing recorded is refused", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.validate_feat_pick(build(), %{feat: @feat, at: 3}, ruleset) ==
               {:error, [{:requires_choice, @feat, :fixture_domain}]}
    end

    test "a choice on a feat that takes none is refused", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.validate_feat_pick(build(), %{feat: @plain, choice: :alpha, at: 3}, ruleset) ==
               {:error, [{:invalid_choice, @plain, :alpha}]}
    end

    # Asking about a build that already contains the pick must not collide it
    # with itself — that is what `:slot` is for, and the feat regression needs it.
    test "the pick being asked about is left out of its own history", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{3 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(
               taken,
               %{feat: @feat, choice: :alpha, at: 3, slot: :general},
               ruleset
             ) == :ok

      assert Rules.validate_feat_pick(taken, %{feat: @feat, choice: :alpha, at: 3}, ruleset) ==
               {:error, [{:choice_already_taken, @feat, :alpha}]}
    end
  end

  # ⚠️ Шестнадцать фитов повторяются, не называя ничего, и это не экзотика:
  # `Epic toughness` на рядовом эпическом билде берут по 10 раз. До этой ветки
  # ядро принимало `repeatable` только с доменом, и все шестнадцать были
  # одноразовыми — осторожность верная, вывод неверный.
  describe "повторяемость без параметра — это счётчик" do
    test "фит берётся столько раз, сколько на него потрачено слотов", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      taken =
        build()
        |> Build.put_feat(1, :general, @counter)
        |> Build.put_feat(3, :general, @counter)

      assert Rules.validate_feat_pick(taken, %{feat: @counter, at: 6}, ruleset) == :ok
      assert Build.feat_takes(taken, @counter, 6) == 2
    end

    # Одноразовость — свойство данных, а не кода: тот же билд с фитом без блока
    # повторяемости отказывает на втором взятии.
    test "а фит без блока повторяемости — по-прежнему один раз", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: @plain}})

      assert Rules.validate_feat_pick(taken, %{feat: @plain, at: 6}, ruleset) ==
               {:error, [{:already_taken, @plain}]}
    end

    # Различаться нечему, значит `distinct` тут неприменим. Проверяется, что он
    # не роняет и не запрещает — раньше `distinct? and choice in previous`
    # прочитало бы два `nil` как дубль.
    test "distinct без домена ничего не запрещает", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, distinct?: true)

      taken =
        build()
        |> Build.put_feat(1, :general, @counter)
        |> Build.put_feat(3, :general, @counter)
        |> Build.put_feat(6, :general, @counter)

      assert Rules.validate_feat_pick(taken, %{feat: @counter, at: 9}, ruleset) == :ok
    end

    test "значение такому фиту предлагать нечего и передавать нельзя", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.feat_choice_candidates(build(), %{feat: @counter, at: 3}, ruleset) ==
               :no_choice

      assert Rules.feat_choice_domain(@counter, ruleset) == nil

      assert Rules.validate_feat_pick(build(), %{feat: @counter, choice: :alpha, at: 3}, ruleset) ==
               {:error, [{:invalid_choice, @counter, :alpha}]}
    end

    # ⚠️ «up to a maximum of 200 hit points» — это потолок ЭФФЕКТА, а эффект фита
    # ядро не считает вовсе. Сколько это взятий — вывести нельзя, и вместо
    # правдоподобной десятки билд получает честный гэп.
    test "без записанного потолка взятий не ограничено, и билд об этом говорит", %{
      ruleset: ruleset
    } do
      ruleset = fixture(ruleset)

      taken =
        Enum.reduce(1..12, build(), fn level, acc ->
          Build.put_feat(acc, level, :general, @counter)
        end)

      assert Rules.validate_feat_pick(taken, %{feat: @counter, at: 13}, ruleset) == :ok
      assert {:missing_data, {:feat_max_takes, @counter}} in Rules.compute(taken, ruleset).gaps
    end

    test "записанный потолок соблюдается, и гэп снимается", %{ruleset: ruleset} do
      ruleset =
        fixture(ruleset, max_takes: %{value: 3, status: "verified", from: nil, quote: nil})

      three =
        build()
        |> Build.put_feat(1, :general, @counter)
        |> Build.put_feat(3, :general, @counter)
        |> Build.put_feat(6, :general, @counter)

      two = Build.truncate(three, 5)

      assert Rules.validate_feat_pick(two, %{feat: @counter, at: 6}, ruleset) == :ok

      assert Rules.validate_feat_pick(three, %{feat: @counter, at: 9}, ruleset) ==
               {:error, [{:max_takes, @counter, 3}]}

      refute {:missing_data, {:feat_max_takes, @counter}} in Rules.compute(three, ruleset).gaps
    end

    # Дан 02.08.2026: `Epic energy resistance` берётся дважды на огонь и один раз
    # на молнию. Значит считается ПАРА, а не фит — три взятия это два одного и
    # одно другого, а не три подряд.
    test "с доменом, где picks могут не отличаться, счёт идёт по паре", %{ruleset: ruleset} do
      ruleset =
        fixture(ruleset,
          distinct?: false,
          max_takes: %{value: 2, status: "verified", from: nil, quote: nil}
        )

      taken =
        build()
        |> Build.put_feat(1, :general, @feat, :alpha)
        |> Build.put_feat(3, :general, @feat, :alpha)

      assert Build.feat_takes(taken, @feat, 6) == 2
      assert Build.feat_takes_by_choice(taken, @feat, 6) == %{alpha: 2}

      # Пара исчерпана…
      assert Rules.validate_feat_pick(taken, %{feat: @feat, choice: :alpha, at: 6}, ruleset) ==
               {:error, [{:max_takes, @feat, 2}]}

      # …а другая — нет.
      assert Rules.validate_feat_pick(taken, %{feat: @feat, choice: :beta, at: 6}, ruleset) == :ok
    end

    # Там, где picks обязаны отличаться, домен и есть потолок: сказать «сколько
    # раз неизвестно» значило бы засчитать оговорку, которая неверна.
    test "при distinct: true потолок взятий не считается неизвестным", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      refute {:missing_data, {:feat_max_takes, @feat}} in Rules.compute(taken, ruleset).gaps
    end

    # Две из восьми записей ручного слоя — догадки Дана, и он сам их так пометил.
    # Правило применяется (никто не утверждает, что фит одноразовый), но
    # применённая догадка, не дающая оговорки, — ровно та тишина из §9.
    test "неподтверждённое правило повторяемости объявлено оговоркой", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, status: "unclear")
      taken = build(%{1 => %{general: @counter}})

      assert {:assumed, {:feat_repeatable, @counter}} in Rules.compute(taken, ruleset).gaps
    end

    test "а подтверждённое — нет", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, status: "verified")
      taken = build(%{1 => %{general: @counter}})

      refute {:assumed, {:feat_repeatable, @counter}} in Rules.compute(taken, ruleset).gaps
    end
  end

  describe "the domain is checked against data, and never against a name in code" do
    test "a value outside the dictionary is refused", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.validate_feat_pick(build(), %{feat: @feat, choice: :delta, at: 3}, ruleset) ==
               {:error, [{:invalid_choice, @feat, :delta}]}
    end

    # `ooze` is in `creature_types.json` with `favored_enemy: false`. The flag is
    # what refuses it; this module has no opinion about oozes.
    test "a value the per-feat gate excludes is refused", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, flags: %{@feat => MapSet.new([:alpha, :beta])})

      assert Rules.validate_feat_pick(build(), %{feat: @feat, choice: :beta, at: 3}, ruleset) ==
               :ok

      assert Rules.validate_feat_pick(build(), %{feat: @feat, choice: :gamma, at: 3}, ruleset) ==
               {:error, [{:invalid_choice, @feat, :gamma}]}
    end

    # Weapons are not modelled and will not be before the armoury. The feat must
    # stay takeable — refusing it would be the opposite lie — and the build has
    # to say the choice went unchecked.
    test "a domain with no dictionary takes the feat and reports the gap", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, values: nil)

      assert Rules.validate_feat_pick(build(), %{feat: @feat, choice: :anything, at: 3}, ruleset) ==
               :ok

      taken = build(%{1 => %{general: {@feat, :anything}}})
      gaps = Rules.compute(taken, ruleset).gaps

      assert {:missing_data, {:choice_domain, :fixture_domain}} in gaps
    end

    test "no dictionaries at all is a gap, not a silent yes", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, domains: %{})
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      gaps = Rules.compute(taken, ruleset).gaps

      assert {:missing_data, {:choice_domain, :fixture_domain}} in gaps
      # …and nothing is declared valid off the back of an absent dictionary.
      assert Rules.feat_choice_candidates(build(), %{feat: @feat, at: 3}, ruleset) ==
               {:error, [{:missing_data, {:choice_domain, :fixture_domain}}]}
    end

    test "the feat's own effect is recorded as unmodelled", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert {:not_modelled, {:feat_bonus, @feat}} in Rules.compute(taken, ruleset).gaps
    end
  end

  # --------------------------------------------------------------------------
  # Кому эта оговорка вообще адресована — задача 3.93
  # --------------------------------------------------------------------------
  #
  # «Прибавку от этого фита в статы не считаем» верно, только если есть стат,
  # в который она падает. Пятнадцать повторяемых фитов из восемнадцати говорили
  # это про урон, ДЦ ЧУЖОГО спасброска, метамагию, сопротивления и маскировку —
  # механики, про которые калькулятор не даёт ответа вовсе, то есть дырки в нём
  # быть не может (CLAUDE.md §9, решение Dan 10.08.2026).
  #
  # ⚠️ Таблица синтетическая, и это не лень: вопрос «как код читает метку»
  # решается формой метки, а не составом `priv/` (тот же приём, что
  # в `gap_receivers_test.exs` и `gear_feats_test.exs`). Живые шестнадцать
  # записей проверяет `Data.FeatEffectReceiversTest` рядом.
  describe "получатель эффекта решает, обязаны ли мы оговариваться" do
    defp labelled(ruleset, receivers) do
      ruleset
      |> fixture()
      |> Map.put(:feat_effect_receivers, %{@feat => %{"affects" => receivers}})
    end

    defp effect_gaps(ruleset) do
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      Rules.compute(taken, ruleset).gaps
    end

    # | метка на фите              | оговорка | почему                          |
    # |----------------------------|----------|---------------------------------|
    # | нет вовсе                  | есть     | забытая метка обязана шуметь    |
    # | все получатели не наши     | НЕТ      | ответа мы про это не даём       |
    # | хоть один наш              | есть     | дырка в ответе настоящая        |
    # | пустой список              | есть     | ничего не утверждает            |
    # | ruleset без словаря        | есть     | нет словаря — нет фильтра       |
    test "метки нет — оговорка остаётся", %{ruleset: ruleset} do
      assert {:not_modelled, {:feat_bonus, @feat}} in effect_gaps(fixture(ruleset))
    end

    test "все получатели не наши — оговорки нет", %{ruleset: ruleset} do
      refute {:not_modelled, {:feat_bonus, @feat}} in effect_gaps(labelled(ruleset, ["damage"]))
    end

    # Правило объявлено в `_receivers._note` и живёт в `GapReceivers.ours?/2`:
    # направление ошибки — в сторону показа.
    test "хватает одного нашего получателя из скольких угодно", %{ruleset: ruleset} do
      gaps = effect_gaps(labelled(ruleset, ["damage", "saving_throws"]))

      assert {:not_modelled, {:feat_bonus, @feat}} in gaps
    end

    test "пустой список — не метка", %{ruleset: ruleset} do
      assert {:not_modelled, {:feat_bonus, @feat}} in effect_gaps(labelled(ruleset, []))
    end

    # ⚠️ Ровно то же правило, по которому `vanilla` не фильтрует ничего: ruleset
    # без словаря получателей обязан говорить ЛИШНЕЕ, а не молчать.
    test "ruleset без словаря получателей фильтра не включает", %{ruleset: ruleset} do
      no_vocabulary =
        ruleset
        |> labelled(["damage"])
        |> Map.delete(:gap_receivers)

      assert {:not_modelled, {:feat_bonus, @feat}} in effect_gaps(no_vocabulary)
    end

    # Отрицательный контроль на саму механику: метка НЕ воскрешает оговорку там,
    # где прибавка посчитана. Два гейта подряд, и «посчитано» стоит первым.
    test "у посчитанного фита метка ничего не меняет", %{ruleset: ruleset} do
      taken = build(%{1 => %{general: :epic_toughness}})

      # Контроль на невакуумность: фит действительно взят и виден тому самому
      # обходу, по которому идут оговорки.
      assert :epic_toughness in Build.feats_taken(taken, 10)

      with_label =
        Map.put(ruleset, :feat_effect_receivers, %{
          epic_toughness: %{"affects" => ["saving_throws"]}
        })

      refute {:not_modelled, {:feat_bonus, :epic_toughness}} in Rules.compute(taken, ruleset).gaps

      refute {:not_modelled, {:feat_bonus, :epic_toughness}} in Rules.compute(taken, with_label).gaps
    end

    test "a build that took no repeatable feat gets neither gap", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      gaps = Rules.compute(build(%{1 => %{general: @plain}}), ruleset).gaps

      refute {:not_modelled, {:feat_bonus, @feat}} in gaps
      refute {:missing_data, {:choice_domain, :fixture_domain}} in gaps
    end

    # Ворота, названные по id фита, не умеют сказать «этого не может взять
    # НИКТО»: `universal` отсекается у `spell_focus`, а у `greater`/`epic` — нет.
    # Общие ворота — это то же самое утверждение, но про значение, а не про фит.
    test "общие ворота домена действуют на все фиты сразу", %{ruleset: ruleset} do
      ruleset =
        fixture(ruleset, flags: %{FeatChoices.domain_gate() => MapSet.new([:alpha, :beta])})

      assert Rules.feat_choice_candidates(build(), %{feat: @feat, at: 3}, ruleset) ==
               {:ok, [:alpha, :beta]}

      assert Rules.validate_feat_pick(build(), %{feat: @feat, choice: :gamma, at: 3}, ruleset) ==
               {:error, [{:invalid_choice, @feat, :gamma}]}
    end

    # …и остаются умолчанием, а не приговором: именованные ворота — исключение
    # поверх общих, иначе «одному можно то, чего нельзя остальным» стало бы
    # невыразимо.
    test "ворота по имени фита перекрывают общие", %{ruleset: ruleset} do
      ruleset =
        fixture(ruleset,
          flags: %{
            FeatChoices.domain_gate() => MapSet.new([:alpha]),
            @feat => MapSet.new([:alpha, :gamma])
          }
        )

      assert Rules.feat_choice_candidates(build(), %{feat: @feat, at: 3}, ruleset) ==
               {:ok, [:alpha, :gamma]}

      # У другого фита того же домена — общие. ⚠️ Базовый фит взят на ОБА
      # значения намеренно: иначе список пуст из-за `same_choice_as`, и проверка
      # ворот зеленела бы, ничего про ворота не сказав (так она и стояла до
      # 03.08.2026 — `{:ok, []}` с комментарием про ворота).
      taken =
        build()
        |> Build.put_feat(1, :general, @feat, :alpha)
        |> Build.put_feat(2, :general, @feat, :gamma)

      assert Rules.feat_choice_candidates(taken, %{feat: @derived, at: 3}, ruleset) ==
               {:ok, [:alpha]}
    end

    # ⚠️ Сторож за состоянием «правильно по совпадению». Сегодня `universal` не
    # доезжает до `greater_spell_focus` только потому, что `same_choice_as`
    # оставляет лишь школы, уже взятые базовым фитом, — то есть дыру закрывает
    # ПОБОЧНЫЙ ЭФФЕКТ другого правила. Проявится она у первого фита со школой,
    # у которого `same_choice_as` нет; этот тест — тот день.
    test "ни один фит не получает словарь с воротами молча", %{ruleset: ruleset} do
      gate = FeatChoices.domain_gate()

      uncovered =
        for {id, feat} <- ruleset.feats,
            is_map(feat.repeatable),
            domain = feat.repeatable.choice,
            not is_nil(domain),
            dictionary = ruleset.choice_domains[domain],
            is_map(dictionary),
            map_size(dictionary.flags) > 0,
            not Map.has_key?(dictionary.flags, gate),
            not Map.has_key?(dictionary.flags, id),
            not covered_by_same_choice?(feat, dictionary, gate),
            do: {id, domain}

      assert uncovered == [],
             """
             У этих фитов домен с воротами, а ворот для них нет — ни общих
             (`#{gate}`), ни именных, ни косвенных через `same_choice_as`.
             Значит им достаётся ПОЛНЫЙ словарь, включая значения, которые
             источник называет невыбираемыми.

             #{inspect(uncovered, pretty: true)}

             Чинится в данных: пометить значение общими воротами
             `"#{gate}": true` у всех выбираемых записей словаря.
             """
    end

    test "the domain a feat draws from is reportable", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.feat_choice_domain(@feat, ruleset) == :fixture_domain
      assert Rules.feat_choice_domain(@plain, ruleset) == nil
    end
  end

  describe "same_choice_as — the qualifier that became a rule" do
    test "the derived feat is legal in a value the base feat already holds", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(taken, %{feat: @derived, choice: :alpha, at: 3}, ruleset) ==
               :ok
    end

    test "and illegal in one it does not", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(taken, %{feat: @derived, choice: :beta, at: 3}, ruleset) ==
               {:error, [{:requires_same_choice, @feat, :beta}]}
    end

    # Until the parser writes the key, the refinement stays a qualifier and this
    # rule must not invent an illegality out of a field nobody filled in.
    test "no key means the old behaviour", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      without =
        put_in(
          ruleset.feats[@derived].prereqs,
          %{"feats" => [Atom.to_string(@feat)]}
        )

      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.validate_feat_pick(taken, %{feat: @derived, choice: :beta, at: 3}, without) ==
               :ok
    end
  end

  describe "candidates — the list the interface offers, computed in the core" do
    test "a feat that takes no parameter says so", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.feat_choice_candidates(build(), %{feat: @plain, at: 3}, ruleset) == :no_choice
    end

    test "the values already used by this feat are gone", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.feat_choice_candidates(taken, %{feat: @feat, at: 3}, ruleset) ==
               {:ok, [:beta, :gamma]}
    end

    test "but only for that feat — the derived one still offers them", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert Rules.feat_choice_candidates(taken, %{feat: @derived, at: 3}, ruleset) ==
               {:ok, [:alpha]}
    end

    test "and the derived feat's own picks are removed in turn", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      taken =
        build()
        |> Build.put_feat(1, :general, @feat, :alpha)
        |> Build.put_feat(2, :general, @feat, :beta)
        |> Build.put_feat(3, :general, @derived, :alpha)

      assert Rules.feat_choice_candidates(taken, %{feat: @derived, at: 6}, ruleset) ==
               {:ok, [:beta]}
    end

    # ⚠️ Здесь стоял тест «a feat with nothing left offers nothing, and is not an
    # error» с ответом `{:ok, []}` — и он был ЗЕЛЁНЫМ на баге. Пустой список
    # означал сразу две разные вещи, а веб-слой знал для него одну
    # формулировку: волшебник, ни разу не бравший `Spell focus`, читал, что все
    # восемь школ у него уже заняты (найдено Dan, 03.08.2026). Дальше — те же
    # два состояния, но с разными ответами.
    test "нечего предложить — это не ошибка, но и не «взято»", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      # Базовый фит не взят ни разу: предлагать нечего ПО ПРЕДУСЛОВИЮ.
      assert Rules.feat_choice_candidates(build(), %{feat: @derived, at: 3}, ruleset) ==
               {:empty, [{:choice_requires, @derived, [@feat], :fixture_domain}]}
    end

    test "израсходованное отличается от неоткрывшегося", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      # Единственное значение, доступное производному фиту, им же и взято.
      taken =
        build()
        |> Build.put_feat(1, :general, @feat, :alpha)
        |> Build.put_feat(2, :general, @derived, :alpha)

      assert Rules.feat_choice_candidates(taken, %{feat: @derived, at: 3}, ruleset) ==
               {:empty, [{:choice_exhausted, @derived, :fixture_domain}]}

      # Положительный контроль: базовый фит на ВТОРОМ значении — и производному
      # снова есть что предложить. Без него оба теста выше зеленели бы и у
      # реализации, которая просто запретила всё.
      opened = Build.put_feat(taken, 3, :general, @feat, :beta)

      assert Rules.feat_choice_candidates(opened, %{feat: @derived, at: 4}, ruleset) ==
               {:ok, [:beta]}
    end

    # Ровно та причина, по которой различие вынесено в ЯДРО, а не в подпись:
    # «занято этим же фитом» прячется, «недоступно по правилам» показывается
    # с причиной (§6), и решать, что именно случилось, веб-слою нечем.
    test "у самого базового фита кончиться могут только собственные взятия",
         %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      all =
        build()
        |> Build.put_feat(1, :general, @feat, :alpha)
        |> Build.put_feat(2, :general, @feat, :beta)
        |> Build.put_feat(3, :general, @feat, :gamma)

      assert Rules.feat_choice_candidates(all, %{feat: @feat, at: 4}, ruleset) ==
               {:empty, [{:choice_exhausted, @feat, :fixture_domain}]}
    end

    # Инвариант, ради которого заведён третий конструктор: пустого `{:ok, []}`
    # больше не существует, и всякий, кто на него матчился, обязан был
    # сломаться — молчаливо он бы читался как «список есть, он пуст».
    test "успешный ответ никогда не пуст", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      builds = [
        build(),
        Build.put_feat(build(), 1, :general, @feat, :alpha),
        build()
        |> Build.put_feat(1, :general, @feat, :alpha)
        |> Build.put_feat(2, :general, @derived, :alpha)
      ]

      for b <- builds, feat <- [@feat, @derived, @plain, @counter] do
        refute match?({:ok, []}, Rules.feat_choice_candidates(b, %{feat: feat, at: 4}, ruleset))
      end
    end

    # Пустой справочник — не справочник, ровно как в `Loader.Reading.resolve_domain/3`:
    # ворота, не пропускающие ничего, это дыра в данных, а не факт о персонаже.
    # Сказать игроку «ты всё выбрал» было бы третьей ложью того же рода.
    test "домен, не дающий фиту ни одного значения, — это пробел в данных",
         %{ruleset: ruleset} do
      ruleset = fixture(ruleset, flags: %{FeatChoices.domain_gate() => MapSet.new([])})

      assert Rules.feat_choice_candidates(build(), %{feat: @feat, at: 3}, ruleset) ==
               {:error, [{:missing_data, {:choice_domain, :fixture_domain}}]}

      taken = build(%{1 => %{general: {@feat, :alpha}}})

      assert {:missing_data, {:choice_domain, :fixture_domain}} in Rules.compute(taken, ruleset).gaps
    end

    test "an unknown feat is an unknown feat", %{ruleset: ruleset} do
      assert Rules.feat_choice_candidates(build(), %{feat: :no_such_feat, at: 3}, ruleset) ==
               {:error, [{:unknown_feat, :no_such_feat}]}
    end

    # Both halves of `validate_feat_pick/3` have an opinion about a feat that is
    # not in the dictionary; the player must not be shown the same fault twice.
    test "an unknown feat is refused once, not once per half", %{ruleset: ruleset} do
      assert Rules.validate_feat_pick(build(), %{feat: :no_such_feat, at: 3}, ruleset) ==
               {:error, [{:unknown_feat, :no_such_feat}]}
    end
  end

  describe "nothing that already reads a build changes" do
    # Растяжка сработала: `repeatable` приехал в данные, и это был правильный
    # момент, чтобы сюда посмотреть. Теперь тест держит противоположное — что
    # повторяемость действительно пришла ИЗ ДАННЫХ и с ней приехало допущение.
    test "повторяемость пришла из данных, и допущение объявлено", %{ruleset: ruleset} do
      repeatable = for {id, feat} <- ruleset.feats, not is_nil(feat[:repeatable]), do: id

      assert repeatable != [], "данные больше не размечают ни одного повторяемого фита"
      assert :spell_focus in repeatable

      # ⚠️ Здесь раньше стояло «домен обязателен у всех» — на том основании, что
      # повторяемый фит без параметра пропускал бы любой дубль. Осторожность была
      # верной, а вывод нет: она отсекала 16 фитов, у которых параметра нет ПО
      # ИСТОЧНИКУ («This feat may be taken multiple times, up to a maximum of 200
      # hit points»), и `Epic toughness` — рядовой эпический фит, а не редкость.
      # Теперь домен обязан быть у тех, кто его называет, а у остальных
      # повторяемость считается количеством пиков.
      for id <- repeatable, not is_nil(ruleset.feats[id].repeatable.choice) do
        assert Map.has_key?(ruleset.choice_domains, ruleset.feats[id].repeatable.choice)
      end

      # У части фитов вики про «должны отличаться» молчит вовсе, и ядро
      # подставляет `true`. Пока хоть один такой есть — допущение обязано
      # стоять в гэпах, а не быть тихим умолчанием. Считаются только те, у кого
      # домен есть: различаться без домена нечему, и допущения там нет.
      assumed? =
        Enum.any?(repeatable, fn id ->
          block = ruleset.feats[id].repeatable
          block.distinct? == true and not block.distinct_stated?
        end)

      assert assumed? == {:assumed, :repeatable_choices_must_differ} in ruleset.gaps
    end

    test "an old-shape build computes exactly as before", %{ruleset: ruleset} do
      old = build(%{1 => %{general: :toughness}, 3 => %{general: :power_attack}})

      assert Rules.compute(old, ruleset).gaps == Rules.compute(old, ruleset).gaps
      assert Build.feats_taken(old, 10) == MapSet.new([:toughness, :power_attack])
    end
  end

  # ---------------------------------------------------------------------------
  # Выбор у ВЫДАННОГО фита (задача 3.26)
  #
  # Класс выдаёт фит, у фита есть параметр — значит выбор есть, а слота нет.
  # Имена и здесь фиктивные: правило не имеет права зависеть от того, что
  # выдающим классом оказался Мастер оружия. Живое число — в
  # `attack_bonuses_test.exs`, на настоящем ruleset'е.
  # ---------------------------------------------------------------------------
  @granting_class :fixture_granting_class

  # Тот же fixture-ruleset, плюс класс, выдающий `@feat` на своём 1-м уровне
  # и `@derived` на 5-м — второй нужен, чтобы проверить `same_choice_as`
  # на выдаче, а не только на пике.
  defp granting(ruleset, opts \\ []) do
    ruleset = fixture(ruleset, opts)
    grants = Keyword.get(opts, :grants, %{1 => [@feat], 5 => [@derived], 6 => [@feat]})

    # ⚠️ Настоящая запись класса как основа, а не сочинённая с нуля: `compute/2`
    # читает у класса хит-дайс, прогрессии и спелл-слоты, и фикстура «только те
    # поля, которые нужны этому пути» падала бы на каждом новом читателе. Своя
    # здесь ровно одна вещь — что и когда класс выдаёт; бонусные слоты убраны,
    # чтобы в тестах про выдачу не появлялось посторонних слотов.
    granting_class =
      ruleset.classes
      |> Map.fetch!(:fighter)
      |> Map.merge(%{
        id: @granting_class,
        granted_feats: grants,
        granted_feat_ranks: %{},
        bonus_feat_levels: MapSet.new(),
        epic_bonus_feat_levels: MapSet.new()
      })

    Map.put(ruleset, :classes, Map.put(ruleset.classes, @granting_class, granting_class))
  end

  defp granted_build(fields \\ []) do
    Build.new([levels: List.duplicate(@granting_class, 10)] ++ fields)
  end

  describe "выбор для фита, который выдал класс" do
    test "уровень выдачи его должен, соседний — нет", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = granted_build()

      assert Rules.granted_feat_choices_owed(b, ruleset, 1) ==
               [%{feat: @feat, domain: :fixture_domain, choice: nil}]

      # ⚠️ Отрицательный контроль в том же тесте: на уровне, где класс не выдаёт
      # ничего с параметром, спрашивать нечего. Порознь первая половина зеленела
      # бы и у кода, который предлагает выбор на каждом уровне.
      assert Rules.granted_feat_choices_owed(b, ruleset, 2) == []

      # Выданный на 5-м фит — тот же механизм, второй фит.
      assert Rules.granted_feat_choices_owed(b, ruleset, 5) ==
               [%{feat: @derived, domain: :fixture_domain, choice: nil}]
    end

    test "записанное значение видно на своём уровне и только на нём", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = Build.put_granted_choice(granted_build(), 1, @feat, :alpha)

      assert Rules.granted_feat_choices_owed(b, ruleset, 1) ==
               [%{feat: @feat, domain: :fixture_domain, choice: :alpha}]

      assert Build.granted_choice(b, 1, @feat) == :alpha
      refute Build.granted_choice(b, 2, @feat)
    end

    test "предлагается весь домен, кроме уже занятого этим же фитом", %{ruleset: ruleset} do
      ruleset = granting(ruleset)

      assert Rules.granted_feat_choice_candidates(granted_build(), ruleset, @feat, 1) ==
               {:ok, [:alpha, :beta, :gamma]}

      # Взятие в СЛОТ забирает значение у выдачи, и наоборот — ключ уникальности
      # один и тот же (`distinct?`), а место хранения на него не влияет. Класс
      # фикстуры выдаёт `@feat` дважды (уровни 1 и 6), поэтому вторая выдача
      # видит и слот, и первую выдачу.
      slotted = granted_build(feats: %{3 => %{general: {@feat, :alpha}}})

      assert Rules.granted_feat_choice_candidates(slotted, ruleset, @feat, 6) ==
               {:ok, [:beta, :gamma]}

      both = Build.put_granted_choice(slotted, 1, @feat, :beta)

      assert Rules.granted_feat_choice_candidates(both, ruleset, @feat, 6) == {:ok, [:gamma]}
      assert Build.feat_choices_permanent(both, ruleset, @feat, 10) == [:alpha, :beta]
    end

    # ⚠️ Порядок уровней здесь такой же, как у всего остального в ядре: история
    # решения — это билд, усечённый до его уровня, поэтому взятие, сделанное
    # ПОЗЖЕ, на выбор выдачи не влияет. Обратное направление влияет: пик после
    # выдачи видит её значение и отбивается. Обе половины одним тестом — порознь
    # каждая зеленела бы и у кода, который читает историю без уровня вовсе.
    test "выдача не видит взятий позже, а взятие после выдачи — видит", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      slotted = granted_build(feats: %{3 => %{general: {@feat, :alpha}}})

      assert Rules.granted_feat_choice_candidates(slotted, ruleset, @feat, 1) ==
               {:ok, [:alpha, :beta, :gamma]}

      granted = Build.put_granted_choice(granted_build(), 1, @feat, :alpha)

      assert Rules.validate_feat_pick(
               granted,
               %{feat: @feat, choice: :alpha, at: 3, slot: :general},
               ruleset
             ) == {:error, [{:choice_already_taken, @feat, :alpha}]}

      # Положительный контроль: другое значение тем же пиком берётся.
      assert Rules.validate_feat_pick(
               granted,
               %{feat: @feat, choice: :beta, at: 3, slot: :general},
               ruleset
             ) == :ok
    end

    # 🔴 ПЕРЕСМОТР, 24.08.2026 (задача 3.84). Этот тест держал ОБРАТНОЕ
    # утверждение — «поздний пик, ставший дублем задним числом, обвинением
    # не становится», — и держал его честно: `illegal_feats/2` спрашивал одни
    # пререквизиты и слотовую бухгалтерию сознательно не перепроверял (так было
    # написано в его доке). Тест стоял свидетелем известного долга, а не
    # желаемого поведения.
    #
    # Долг закрыт, и закрыл его КРИТЕРИЙ, который уже был записан рядом: одну
    # слотовую проверку (`FeatSlots.choice_refusals/4`) переспрашивали потому,
    # что «its absence would be a false legality reachable without hand-editing
    # anything». Случай Dan этому критерию отвечает — дубль получается обычным
    # редактированием через интерфейс, — значит `illegal_feats/2` спрашивает
    # `validate_feat_pick/3` целиком, и дубль обвиняется.
    #
    # ⚠️ Обвиняется ПОЗДНИЙ из двух, и здесь это выдача на 1-м против пика на
    # 3-м: история решения — билд, усечённый до его уровня, поэтому пик видит
    # выдачу, а выдача пика не видит. Это не разрешение спора монеткой, а
    # порядок игры: на 3-м уровне значение уже занято и предложено не было бы.
    test "поздний пик, ставший дублем задним числом, ОБВИНЯЕТСЯ", %{
      ruleset: ruleset
    } do
      ruleset = granting(ruleset)

      clashing =
        granted_build(feats: %{3 => %{general: {@feat, :alpha}}})
        |> Build.put_granted_choice(1, @feat, :alpha)

      assert {3, :general, @feat, {:choice_already_taken, @feat, :alpha}} in Rules.illegal_feats(
               clashing,
               ruleset
             )

      # ⚠️ Отрицательный контроль к нему же, и он про НАПРАВЛЕНИЕ: уровень
      # выдачи (1) обвинением не становится. Порознь `assert` выше зеленел бы
      # и у кода, который обвиняет оба уровня разом, — а такой код запрещал бы
      # законное «перенести фит раньше».
      refute Enum.any?(Rules.illegal_feats(clashing, ruleset), &match?({1, _, _, _}, &1))

      # Положительный контроль к тому же вызову, доставшийся от прежней редакции
      # теста: требования, которые он ПРОВЕРЯЕТ, он и находит. Билд взят БЕЗ
      # выдающего класса, иначе `@feat` у персонажа есть и требованию не на что
      # жаловаться.
      broken = build(%{3 => %{general: {@derived, :alpha}}})

      assert Enum.any?(
               Rules.illegal_feats(broken, ruleset),
               &match?({3, :general, @derived, {:requires_feat, @feat}}, &1)
             )
    end

    test "своё же значение не считается дублем самого себя", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = Build.put_granted_choice(granted_build(), 1, @feat, :alpha)

      # Переклик по уже выбранному — это замена, а не второе взятие: значение
      # обязано остаться в списке и пройти проверку.
      assert Rules.granted_feat_choice_candidates(b, ruleset, @feat, 1) ==
               {:ok, [:alpha, :beta, :gamma]}

      assert Rules.validate_granted_feat_choice(b, ruleset, @feat, :alpha, 1) == :ok
    end

    # 🔴 Половина задачи, которую нельзя ослабить: выданный фит проверяет своё
    # требование «с тем же выбором» ровно как пик в слоте.
    test "same_choice_as держится и на выдаче", %{ruleset: ruleset} do
      ruleset = granting(ruleset)

      # `@derived` требует `@feat` с тем же значением. Ни одного `@feat` нет —
      # предлагать нечего, и причина называет требуемый фит, а не «всё занято».
      assert Rules.granted_feat_choice_candidates(granted_build(), ruleset, @derived, 5) ==
               {:empty, [{:choice_requires, @derived, [@feat], :fixture_domain}]}

      assert Rules.validate_granted_feat_choice(granted_build(), ruleset, @derived, :alpha, 5) ==
               {:error, [{:requires_same_choice, @feat, :alpha}]}

      # Положительный контроль той же пары: с `@feat` на `:alpha` выдача
      # `@derived` принимает `:alpha` и только его.
      with_base = granted_build(feats: %{3 => %{general: {@feat, :alpha}}})

      assert Rules.granted_feat_choice_candidates(with_base, ruleset, @derived, 5) ==
               {:ok, [:alpha]}

      assert Rules.validate_granted_feat_choice(with_base, ruleset, @derived, :alpha, 5) == :ok

      assert Rules.validate_granted_feat_choice(with_base, ruleset, @derived, :beta, 5) ==
               {:error, [{:requires_same_choice, @feat, :beta}]}
    end

    # ⚠️ И обратная сторона: значение, ВЫДАННОЕ классом, тоже удовлетворяет
    # `same_choice_as` — иначе выдача считалась бы половиной факта.
    test "выданное значение удовлетворяет требование другого фита", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = Build.put_granted_choice(granted_build(), 1, @feat, :beta)

      assert Rules.granted_feat_choice_candidates(b, ruleset, @derived, 5) == {:ok, [:beta]}

      assert Rules.validate_feat_pick(
               b,
               %{feat: @derived, choice: :beta, at: 6, slot: :general},
               ruleset
             ) == :ok
    end

    test "значение вне домена и фит, которого уровень не выдаёт", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = granted_build()

      assert Rules.validate_granted_feat_choice(b, ruleset, @feat, :not_a_value, 1) ==
               {:error, [{:invalid_choice, @feat, :not_a_value}]}

      # Уровень 2 этот фит не выдаёт — выбирать не для чего. Кликом не доехать,
      # но правленой ссылкой можно, и тогда причина обязана быть словами.
      assert Rules.validate_granted_feat_choice(b, ruleset, @feat, :alpha, 2) ==
               {:error, [{:not_granted, @feat}]}

      assert Rules.granted_feat_choice_candidates(b, ruleset, @feat, 2) ==
               {:error, [{:not_granted, @feat}]}
    end

    test "фит без параметра выбора не принимает, а неизвестный — неизвестен", %{ruleset: ruleset} do
      ruleset = granting(ruleset)

      ruleset = granting(ruleset, grants: %{1 => [@feat, @plain]})
      b = granted_build()

      assert Rules.granted_feat_choice_candidates(b, ruleset, @plain, 1) == :no_choice

      assert Rules.validate_granted_feat_choice(b, ruleset, @plain, :alpha, 1) ==
               {:error, [{:invalid_choice, @plain, :alpha}]}

      assert Rules.granted_feat_choice_candidates(b, ruleset, :no_such_feat, 1) ==
               {:error, [{:unknown_feat, :no_such_feat}]}
    end

    # Выдача — не пик, и это видно по счётчикам: слот на неё не тратится, а
    # значение при этом у персонажа есть. Обе половины одним тестом — порознь
    # каждая зеленела бы и на модели, где выдача лежит в слоте.
    test "выдача не занимает слот и не считается взятием", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = Build.put_granted_choice(granted_build(), 1, @feat, :alpha)

      assert Build.feats_at(b, 1) == []
      assert Build.feat_takes(b, @feat, 10) == 0
      assert Build.feat_choices(b, @feat, 10) == []

      assert Build.feat_choices_permanent(b, ruleset, @feat, 10) == [:alpha]
      assert Build.granted_feat_choices(b, ruleset, @feat, 10) == [:alpha]
    end

    test "усечение билда отрезает выбор выдачи вместе с уровнем", %{ruleset: ruleset} do
      ruleset = granting(ruleset)
      b = Build.put_granted_choice(granted_build(), 5, @derived, :alpha)

      assert Build.feat_choices_permanent(b, ruleset, @derived, 10) == [:alpha]
      assert Build.feat_choices_permanent(Build.truncate(b, 4), ruleset, @derived, 4) == []

      # Дельта уровня считается как разность двух полных `compute` (CLAUDE.md §5),
      # поэтому выбор, сделанный на 5-м, не имеет права влиять на 4-й.
      assert Build.truncate(b, 4).granted_choices == %{}
    end

    # ⚠️ Записанное значение не является доказательством выдачи: класс уровня
    # можно поменять, и строка останется — ровно как остаются пики уровня.
    test "выбор на уровне, который этот фит больше не выдаёт, не считается", %{ruleset: ruleset} do
      ruleset = granting(ruleset)

      b = Build.put_granted_choice(granted_build(), 1, @feat, :alpha)
      assert Build.feat_choices_permanent(b, ruleset, @feat, 10) == [:alpha]

      moved = Build.replace_level(b, 1, :fighter)

      assert Build.granted_choice(moved, 1, @feat) == :alpha
      assert Build.feat_choices_permanent(moved, ruleset, @feat, 10) == []
    end

    test "снятое значение стирает уровень целиком", %{ruleset: _ruleset} do
      b =
        granted_build()
        |> Build.put_granted_choice(1, @feat, :alpha)
        |> Build.put_granted_choice(1, @feat, nil)

      # Пустой уровень не остаётся `%{}`: «выбрал и снял» обязан быть тем же
      # билдом, что «не выбирал», иначе у него другой код в ссылке.
      assert b.granted_choices == %{}
    end
  end

  # --------------------------------------------------------------------------
  # Четвёртый маршрут выбора — ПРЕДМЕТ (задача 3.97)
  # --------------------------------------------------------------------------
  #
  # Слот, выдача класса, импортированная строка — и вещь. Машинерия одна и та
  # же (`values/3` и его ворота, `offer/5`), а различаются маршруты ровно двумя
  # фильтрами. У вещи оба **шире**, и оба — правило `Rules.GearFeats`, а не
  # срез угла:
  #
  #   * про персонажа не спрашивается ничего, `same_choice_as` в том числе:
  #     объявленный фит не проверяется против собственных требований;
  #   * уровня нет: `Build.truncate/2` вещи не трогает.
  #
  # Фикстуры синтетические, как и во всём файле: контроль на живой записи
  # завтра получает правку данных и молча перестаёт что-либо проверять.

  defp gear_build(feats, fields \\ []) do
    Build.new([levels: List.duplicate(:ranger, 10), gear: %Gear{feats: feats}] ++ fields)
  end

  describe "выбор для фита, объявленного с вещи" do
    test "предлагается весь домен, кроме уже объявленного этим же фитом", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.gear_feat_choice_candidates(gear_build([@feat]), ruleset, @feat) ==
               {:ok, [:alpha, :beta, :gamma]}

      assert Rules.gear_feat_choice_candidates(gear_build([{@feat, :alpha}]), ruleset, @feat) ==
               {:ok, [:beta, :gamma]}

      # ⚠️ Слот значение у ВЕЩИ не забирает: это два разных объявления одного
      # легального билда, и «ты уже взял эту школу» про амулет неправда.
      slotted = gear_build([@feat], feats: %{3 => %{general: {@feat, :alpha}}})

      assert Rules.gear_feat_choice_candidates(slotted, ruleset, @feat) ==
               {:ok, [:alpha, :beta, :gamma]}
    end

    # 🔴 Главное отличие маршрута, и оно измерено (H7): объявление против
    # собственных требований не проверяется вовсе, значит `same_choice_as`
    # список не режет. Отрицательный контроль — тот же билд слотом.
    test "same_choice_as список вещи не режет, а список слота — режет", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      b = gear_build([@derived])

      assert Rules.gear_feat_choice_candidates(b, ruleset, @derived) ==
               {:ok, [:alpha, :beta, :gamma]}

      assert Rules.feat_choice_candidates(b, @derived, ruleset) ==
               {:empty, [{:choice_requires, @derived, [@feat], :fixture_domain}]}

      # И проверка значения тем же двум маршрутам отвечает по-разному.
      assert Rules.validate_gear_feat_choice(b, ruleset, @derived, :alpha) == :ok

      assert Rules.validate_feat_pick(
               b,
               %{feat: @derived, choice: :alpha, at: 3, slot: :general},
               ruleset
             ) == {:error, [{:requires_feat, @feat}, {:requires_same_choice, @feat, :alpha}]}
    end

    test "значение вне домена отбивается, а его отсутствие — нет", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      b = gear_build([@feat])

      assert Rules.validate_gear_feat_choice(b, ruleset, @feat, :delta) ==
               {:error, [{:invalid_choice, @feat, :delta}]}

      # 🔴 `nil` — законное состояние объявления, а не отказ: так записаны ВСЕ
      # ссылки старше задачи 3.97 (решение Dan, 25.08.2026). Слот на том же
      # месте требует выбрать.
      assert Rules.validate_gear_feat_choice(b, ruleset, @feat, nil) == :ok

      assert Rules.validate_feat_pick(b, %{feat: @feat, at: 3, slot: :general}, ruleset) ==
               {:error, [{:requires_choice, @feat, :fixture_domain}]}
    end

    test "значение на фите без параметра отбивается", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.validate_gear_feat_choice(gear_build([@plain]), ruleset, @plain, :alpha) ==
               {:error, [{:invalid_choice, @plain, :alpha}]}

      assert Rules.gear_feat_choice_candidates(gear_build([@plain]), ruleset, @plain) ==
               :no_choice

      # Счётчик — тот же ответ: повторяется, а называть нечего.
      assert Rules.gear_feat_choice_candidates(gear_build([@counter]), ruleset, @counter) ==
               :no_choice
    end

    test "то же значение вторым объявлением того же фита отбивается", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)
      b = gear_build([{@feat, :alpha}])

      assert Rules.validate_gear_feat_choice(b, ruleset, @feat, :alpha) ==
               {:error, [{:choice_already_taken, @feat, :alpha}]}

      # Положительный контроль: другое значение тем же фитом объявляется.
      assert Rules.validate_gear_feat_choice(b, ruleset, @feat, :beta) == :ok

      # И там, где данные НЕ требуют различия, повтор не отбивается.
      same_allowed = fixture(ruleset, distinct?: false)

      assert Rules.validate_gear_feat_choice(b, same_allowed, @feat, :alpha) == :ok
    end

    # Ворота домена — те же самые, что у слота, и это весь довод против второй
    # реализации: значение, закрытое пер-фитовым флагом словаря, не проходит ни
    # одним маршрутом.
    test "пер-фитовые ворота словаря действуют и на вещь", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, flags: %{@feat => MapSet.new([:alpha])})

      assert Rules.gear_feat_choice_candidates(gear_build([@feat]), ruleset, @feat) ==
               {:ok, [:alpha]}

      assert Rules.validate_gear_feat_choice(gear_build([@feat]), ruleset, @feat, :beta) ==
               {:error, [{:invalid_choice, @feat, :beta}]}

      # И `Rules.GearFeats` судит объявление тем же чтением, без билда вовсе:
      # запись отбита, владение не засчитано, а причина названа поимённо.
      gear = %Gear{feats: [{@feat, :beta}]}

      assert Rules.validate_gear_feat({@feat, :beta}, ruleset) ==
               {:error, [{:invalid_choice, @feat, :beta}]}

      assert Rules.validate_gear_feat({@feat, :alpha}, ruleset) == :ok
      assert Rules.validate_gear_feat(@feat, ruleset) == :ok

      assert Rules.illegal_gear_feats(gear_build([{@feat, :beta}]), ruleset) ==
               [{@feat, {:invalid_choice, @feat, :beta}}]

      refute MapSet.member?(GearFeats.held(gear, ruleset), @feat)
    end

    test "домен без словаря: сказать нечего, и это отдельный ответ", %{ruleset: ruleset} do
      ruleset = fixture(ruleset, values: nil)

      assert Rules.gear_feat_choice_candidates(gear_build([@feat]), ruleset, @feat) ==
               {:error, [{:missing_data, {:choice_domain, :fixture_domain}}]}

      # Отказать при этом нельзя: значение записано, а судить его нечем.
      assert Rules.validate_gear_feat_choice(gear_build([@feat]), ruleset, @feat, :delta) == :ok
    end

    test "фита нет в ruleset'е", %{ruleset: ruleset} do
      ruleset = fixture(ruleset)

      assert Rules.gear_feat_choice_candidates(gear_build([]), ruleset, :not_a_feat) ==
               {:error, [{:unknown_feat, :not_a_feat}]}

      assert Rules.validate_gear_feat_choice(gear_build([]), ruleset, :not_a_feat, :alpha) ==
               {:error, [{:unknown_feat, :not_a_feat}]}
    end
  end
end
