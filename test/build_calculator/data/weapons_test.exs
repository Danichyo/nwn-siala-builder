defmodule BuildCalculator.Data.WeaponsTest do
  @moduledoc """
  Оружие как домен выбора — задача 3.5, часть A.

  До неё `ruleset.choice_domains[:weapon]` был `%{values: nil, …}`, и восемь
  фитов брались с выбором, которого никто не проверял. Здесь пришпилено то,
  что после появления `priv/rules/vanilla/weapons.json` стало проверяемым, и —
  отдельно и не менее важно — то, что проверяемым **не** стало.

  ⚠️ Порядок утверждений в файле отвечает на разные вопросы, и путать их нельзя:

    * словарь собран и подключён;
    * ворота отсекают ровно то, что источник называет невыбираемым;
    * `same_choice_as` наконец срабатывает — то, ради чего Dan просил задачу;
    * оговорка про **владение** осталась оговоркой, потому что владение мы
      по-прежнему не проверяем;
    * сиальская таксономия — наша, а не прочитанная, и это видно в данных.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, FeatChoices}

  @gate FeatChoices.domain_gate()

  # Шесть, которые ни один оружейный фит не принимает В ВАНИЛИ. Четыре из них —
  # формы атаки существа, пятое — посох, шестое — копьё-лэнс; у последних двух
  # причина написана прозой на странице `Weapon focus` («There is no version of
  # this feat for the magic staff or lance»).
  @not_selectable [
    :bite_item,
    :claw_item,
    :gore_item,
    :lance,
    :magic_staff,
    :slam_item
  ]

  # На Сиале седьмое, и это ЗАМЕР, а не чтение (Dan, 26.08.2026,
  # `GAME_CHECKS.md` AC6): «взял все 5 владений оружиями, что открыло weapon
  # focus ко всем возможным типам оружия, и creature weapon среди них нет».
  # ⚠️ Ваниль не тронута: `Weapon focus (Creature weapon)` — законный выбор
  # оборотня и друида в NWN, и замер на шарде про ваниль не говорит ничего.
  @not_selectable_on_shard Enum.sort([:creature_weapon | @not_selectable])

  setup_all do
    raw =
      [File.cwd!(), "priv/rules/vanilla/weapons.json"]
      |> Path.join()
      |> File.read!()
      |> Jason.decode!()

    %{vanilla: Data.ruleset!("vanilla"), siala: Data.ruleset!("siala_41"), raw: raw}
  end

  defp weapons(raw), do: Map.new(raw["weapons"], &{&1["id"], &1})

  defp feats_choosing(ruleset) do
    for {id, feat} <- ruleset.feats,
        is_map(feat.repeatable),
        feat.repeatable.choice == :weapon,
        do: id
  end

  describe "словарь подключён" do
    # ⚠️ Найдено порчей при исполнении 3.5, а не предположено: подменённый
    # `weapons.json` НЕ пересобрал ruleset — файл был накрыт только записью
    # каталога `"vanilla"`, а mtime каталога от правки файла не двигается.
    # Тот же урок, что `spellcasting_test.exs` записал за волной 5.
    test "зарегистрирован по имени, а не только каталогом" do
      assert "vanilla/weapons.json" in BuildCalculator.Data.Loader.source_files()
    end

    test "домен разрешается в файл, а не в дыру", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        domain = Map.fetch!(ruleset.choice_domains, :weapon)

        assert domain.source == :file
        assert MapSet.size(domain.values) == 47
        refute {:missing_data, {:choice_domain, :weapon}} in ruleset.gaps
      end
    end

    # ⚠️ Главное следствие задачи для всего файла ядра: `weapon` был последним
    # неразрешимым доменом. Если этот тест покраснеет вниз, значит домен
    # потеряли; если вверх — появился новый, и тогда его надо разобрать, а
    # не радоваться.
    test "неразрешимых доменов не осталось ни одного", %{vanilla: vanilla, siala: siala} do
      for ruleset <- [vanilla, siala] do
        unresolved = for {name, d} <- ruleset.choice_domains, is_nil(d.values), do: name
        assert unresolved == []
      end
    end

    test "у каждого оружия есть источник с revid и датой", %{raw: raw} do
      for weapon <- raw["weapons"] do
        assert weapon["source"]["wiki"] == "fandom"
        assert is_integer(weapon["source"]["revid"])
        assert weapon["source"]["page"] == weapon["name"]
        assert weapon["source"]["fetched"] =~ ~r/^\d{4}-\d{2}-\d{2}$/
      end
    end
  end

  describe "ворота домена" do
    test "оружие выбирают четыре фита в ванили и шесть на Сиале", %{
      vanilla: vanilla,
      siala: siala
    } do
      # Положительный контроль ко всем проверкам ниже: если это упадёт, значит
      # проверяемые фиты вообще не попали в поле зрения.
      assert Enum.sort(feats_choosing(vanilla)) ==
               [:improved_critical, :weapon_focus, :weapon_of_choice, :weapon_specialization]

      # Сиала делает повторяемыми ещё два эпических (Dan, 02.08.2026).
      assert :epic_weapon_focus in feats_choosing(siala)
      assert :epic_weapon_specialization in feats_choosing(siala)
    end

    # ⚠️ Ruleset'ы отвечают РАЗНО с 26.08.2026 (задача 3.108), и оба числа стоят
    # рядом намеренно: одна половина без другой зеленела бы и при правке,
    # уехавшей не в тот слой. Ровно так 16.08.2026 лэнс исчез у ванили — блок
    # положили в секцию, которую видят оба, — и поймано это было прогоном.
    test "41 из 47 выбираемы в ванили и 40 на Сиале, отсечено ровно названное", %{
      vanilla: vanilla,
      siala: siala
    } do
      for {ruleset, size, cut} <- [
            {vanilla, 41, @not_selectable},
            {siala, 40, @not_selectable_on_shard}
          ] do
        domain = Map.fetch!(ruleset.choice_domains, :weapon)
        gate = Map.fetch!(domain.flags, @gate)

        assert MapSet.size(gate) == size

        assert domain.values |> MapSet.difference(gate) |> MapSet.to_list() |> Enum.sort() == cut
      end
    end

    test "Weapon focus предлагает 41 в ванили и 40 на Сиале", %{
      vanilla: vanilla,
      siala: siala
    } do
      pick = %{feat: :weapon_focus, at: 41}

      assert {:ok, vanilla_values} = FeatChoices.candidates(%Build{}, pick, vanilla)
      assert {:ok, siala_values} = FeatChoices.candidates(%Build{}, pick, siala)

      assert length(vanilla_values) == 41
      assert length(siala_values) == 40

      for values <- [vanilla_values, siala_values] do
        refute :magic_staff in values
        refute :lance in values
      end

      # 🔴 Единственная разница между ruleset'ами, и она в обе стороны:
      # на Сиале варианта нет (замер AC6), в ванили он законен.
      refute :creature_weapon in siala_values
      assert :creature_weapon in vanilla_values

      # Положительный контроль рядом с refute: посох в словаре ЕСТЬ, то есть
      # проверка про отсечение, а не про отсутствие значения. То же и с оружием
      # существа — из справочника оно никуда не делось, закрыты только ворота.
      assert MapSet.member?(siala.choice_domains[:weapon].values, :magic_staff)
      assert MapSet.member?(siala.choice_domains[:weapon].values, :creature_weapon)
    end

    # 🔴 Ворота ДОМЕН-ШИРОКИЕ, и проверить это надо на втором фите: замер видел
    # список у `Weapon focus`, а закрывается значение у всей семьи сразу —
    # так устроен справочник (`_chosen_by.corroborated_by`: семь страниц
    # называют один и тот же набор). `Improved critical` берётся сам по себе,
    # без `same_choice_as`, поэтому он тут и стоит: у остальных членов семьи
    # значение и так не появилось бы — их список выводится из `Weapon focus`.
    test "закрытое значение исчезает у всей семьи, а не у названного фита", %{
      vanilla: vanilla,
      siala: siala
    } do
      pick = %{feat: :improved_critical, at: 41}

      assert {:ok, vanilla_values} = FeatChoices.candidates(%Build{}, pick, vanilla)
      assert {:ok, siala_values} = FeatChoices.candidates(%Build{}, pick, siala)

      assert :creature_weapon in vanilla_values
      refute :creature_weapon in siala_values

      # Положительный контроль: остальной список у фита тот же, разница ровно
      # в одном значении.
      assert Enum.sort(vanilla_values -- [:creature_weapon]) == Enum.sort(siala_values)
    end

    # Именные ворота поверх домен-широких — тот же приём, что `favored_enemy`
    # у типов существ. `Weapon of choice` уже, чем весь домен: только ближний
    # бой, и минус четыре названных.
    test "Weapon of choice получает 31, без дальнего боя и без рукопашного", %{siala: siala} do
      domain = Map.fetch!(siala.choice_domains, :weapon)
      gate = Map.fetch!(domain.flags, :weapon_of_choice)

      assert MapSet.size(gate) == 31
      refute MapSet.member?(gate, :longbow)
      refute MapSet.member?(gate, :unarmed_strike)
      refute MapSet.member?(gate, :creature_weapon)

      # И положительный контроль: ближний бой в воротах есть.
      assert MapSet.member?(gate, :longsword)
    end

    # ⚠️ Ловушка, которую невозможно увидеть глазами: `Loader.Reading.entry_flags/1`
    # индексирует КАЖДОЕ булево поле записи, а `FeatChoices` ищет ворота по id
    # фита. Поле `ranged` у оружия — описание, но если бы фит назывался
    # `ranged`, он молча получил бы восемь дальнобойных вместо своего списка.
    test "описательные булевы поля не становятся воротами чужого фита", %{siala: siala} do
      flags = Map.fetch!(siala.choice_domains, :weapon).flags

      # Ворот именных ровно одни — у того фита, для кого источник их и называет.
      named = for {name, _set} <- flags, Map.has_key?(siala.feats, name), do: name
      assert named == [:weapon_of_choice]

      # Положительный контроль: описательные поля в flags действительно лежат,
      # то есть проверка выше видит их и признаёт неопасными.
      assert Map.has_key?(flags, :ranged)
      assert Map.has_key?(flags, :double_sided)
    end
  end

  describe "same_choice_as наконец срабатывает" do
    # Дословный запрос Dan: «Если взял обычный фокус на условный длинный меч,
    # то сможешь взять потом эпик фокус». Проверяется на ванильной паре, которая
    # работает в обоих ruleset'ах.
    test "специализация берётся только в оружии взятого фокуса", %{vanilla: vanilla} do
      fighter = %Build{race: :human, levels: List.duplicate(:fighter, 8)}
      took = Build.put_feat(fighter, 1, {:class_bonus, :fighter}, :weapon_focus, :longsword)

      assert FeatChoices.candidates(took, %{feat: :weapon_specialization, at: 8}, vanilla) ==
               {:ok, [:longsword]}

      assert {:requires_same_choice, :weapon_focus, :rapier} in FeatChoices.reasons(
               took,
               %{feat: :weapon_specialization, choice: :rapier, at: 8},
               vanilla
             )

      # Положительный контроль: то же оружие не отбивается по этой причине.
      refute Enum.any?(
               FeatChoices.reasons(
                 took,
                 %{feat: :weapon_specialization, choice: :longsword, at: 8},
                 vanilla
               ),
               &match?({:requires_same_choice, _, _}, &1)
             )
    end

    # ⚠️ Именные ворота и `same_choice_as` работают ВМЕСТЕ, и порядок важен:
    # `Weapon of choice` — только ближний бой, поэтому фокус, взятый на лук,
    # его не открывает вовсе. Без ворот мастер оружия получил бы «оружие выбора»
    # на длинный лук — нелегальный билд, который источник запрещает прозой.
    test "оружие выбора не открывается фокусом на лук", %{siala: siala} do
      master =
        %Build{
          race: :human,
          levels: List.duplicate(:fighter, 10) ++ List.duplicate(:weapon_master, 10),
          base_abilities: %{str: 18, dex: 16, con: 14, int: 12, wis: 10, cha: 8}
        }

      bow = Build.put_feat(master, 1, {:class_bonus, :fighter}, :weapon_focus, :longbow)

      assert {:invalid_choice, :weapon_of_choice, :longbow} in FeatChoices.reasons(
               bow,
               %{feat: :weapon_of_choice, choice: :longbow, at: 20},
               siala
             )

      # Положительный контроль: тот же билд с фокусом на ближнее оружие получает
      # ровно его, то есть отказ выше — про дальний бой, а не про фит целиком.
      both = Build.put_feat(bow, 2, {:class_bonus, :fighter}, :weapon_focus, :longsword)

      assert FeatChoices.candidates(both, %{feat: :weapon_of_choice, at: 20}, siala) ==
               {:ok, [:longsword]}
    end

    # У кого фокуса нет вовсе — «нужен Weapon focus», а не «всё уже взято».
    # Две разные причины опустеть, и до 3.5 обе выглядели как отсутствие домена.
    test "без базового фокуса причина — требование, а не исчерпание", %{vanilla: vanilla} do
      assert FeatChoices.candidates(%Build{}, %{feat: :weapon_specialization, at: 8}, vanilla) ==
               {:empty, [{:choice_requires, :weapon_specialization, [:weapon_focus], :weapon}]}
    end

    # Оговорка снята ровно у двух фитов — у тех, где она стала правилом.
    test "снятая оговорка снята, оставшиеся остались", %{vanilla: vanilla} do
      for id <- [:weapon_specialization, :weapon_of_choice] do
        assert Rules.feat_caveats(id, vanilla) == [], "#{id}: оговорка осталась после переезда"
      end

      # ⚠️ Здесь стояло: «А эти две — про ВЛАДЕНИЕ, и владение мы не проверяем:
      # маппинга сиальских категорий на конкретное оружие нет (решение Dan
      # 10.08.2026)». УСТАРЕЛО ДВАЖДЫ: маппинг сверен Dan 16.08.2026 (42
      # `verified` из 47), а задача 3.99 сделала требование проверяемым ключом
      # `proficiency_with_chosen_weapon`. Оговорки нет ни на одном ruleset'е —
      # но ОТВЕТ у них разный, и это разница данных, а не правила.
      for id <- [:weapon_focus, :improved_critical] do
        assert Rules.feat_caveats(id, vanilla) == [], "#{id}: оговорка осталась после переезда"
      end
    end

    # Правило одно, ответ разный: у Сиалы владение названо, у ванили — нет.
    test "владение проверяется там, где справочник его называет", %{
      vanilla: vanilla,
      siala: siala
    } do
      fighter =
        %Build{
          race: :human,
          levels: List.duplicate(:fighter, 8),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8}
        }

      pick = %{feat: :weapon_focus, choice: :scimitar, at: 9}

      assert Rules.validate_feat(fighter, pick, siala) ==
               {:error, [{:requires_feat, :siala_blade_proficiency}]}

      # Положительный контроль номер один: с владением тот же выбор законен.
      with_proficiency = Build.put_feat(fighter, 1, :general, :siala_blade_proficiency)
      assert Rules.validate_feat(with_proficiency, pick, siala) == :ok

      # Положительный контроль номер два: у ванили справочник владения
      # не называет (`:unread` у 43 записей из 47), поэтому отказать нечем
      # и требование молчит — как молчало до задачи 3.99.
      assert Rules.validate_feat(fighter, pick, vanilla) == :ok
    end
  end

  describe "чего словарь НЕ закрыл" do
    # ⚠️ Здесь стояло «билд с Weapon focus несёт оговорку про владение», и она
    # была общей — одна фраза на любой билд. Задача 3.99 сделала требование
    # проверяемым, и оговорка стала ТОЧЕЧНОЙ: она называет ОРУЖИЕ, владения
    # для которого не назвал никто, и только его.
    #
    # 🔴 А задача 3.108 сделала её на Сиале НЕДОСТИЖИМОЙ ЛЕГАЛЬНОЙ ИГРОЙ, и это
    # надо было заметить, а не узнать потом. Здесь стояло «на Сиале такая запись
    # ровно одна из сорока одной выбираемой»: единственное оружие с непрочитанным
    # владением, которое шард вообще предлагал, — `creature_weapon`, и замер AC6
    # убрал его из предложения. Оговорка от этого не выброшена и не должна быть:
    # `compute/2` честен про то, что в билде лежит, куда бы оно ни попало —
    # ссылкой со старым билдом, импортом, правкой руками, — а форму держит живой
    # ваниль, где `:unread` у 43 записей из 47. Соседний тест ниже проверяет
    # ровно эту недостижимость, чтобы её нельзя было спутать с пропажей правила.
    test "оговорка про владение осталась там, где справочник молчит", %{
      vanilla: vanilla,
      siala: siala
    } do
      build = fn weapon ->
        %Build{
          race: :human,
          levels: List.duplicate(:fighter, 6),
          base_abilities: %{str: 16, dex: 12, con: 14, int: 12, wis: 10, cha: 8},
          feats: %{1 => %{{:class_bonus, :fighter} => {:weapon_focus, weapon}}}
        }
      end

      # Оружие существа: своей группы владения у него нет ни на одном ruleset'е.
      for ruleset <- [vanilla, siala] do
        assert {:missing_data, {:weapon_proficiency, :creature_weapon}} in Rules.compute(
                 build.(:creature_weapon),
                 ruleset
               ).gaps
      end

      # Положительный контроль: у названного оружия оговорки нет — владение
      # проверено, и печатать «не проверяем» было бы ложной неопределённостью.
      refute {:missing_data, {:weapon_proficiency, :longsword}} in Rules.compute(
               build.(:longsword),
               siala
             ).gaps

      # А у ванили молчит справочник, и билд говорит об этом сам.
      assert {:missing_data, {:weapon_proficiency, :longsword}} in Rules.compute(
               build.(:longsword),
               vanilla
             ).gaps

      # Положительный контроль: старая оговорка про отсутствие домена ушла,
      # то есть список гэпов действительно пересчитан, а не тот же самый.
      refute {:missing_data, {:choice_domain, :weapon}} in Rules.compute(
               build.(:longsword),
               siala
             ).gaps
    end

    # 🔴 Следствие 3.108, названное вслух: на Сиале эту оговорку больше не может
    # получить ни один билд, собранный по правилам. Оружия с непрочитанным
    # владением там пять — все пять форм атаки существа, — и ни одно из них
    # шард не предлагает: четыре не выбирались никогда, пятое закрыл замер AC6.
    #
    # ⚠️ Это НЕ «правило исчезло»: у ванили оно живёт на 43 записях из 47, и
    # соседний тест выше это держит. Появится на Сиале выбираемое оружие,
    # которого её пять фитов владения не называют, — оговорка вернётся сама.
    test "на Сиале оговорка стала недостижимой: у всего предлагаемого владение прочитано",
         %{vanilla: vanilla, siala: siala} do
      unread = fn ruleset ->
        gate = Map.fetch!(ruleset.choice_domains[:weapon].flags, @gate)

        for {id, weapon} <- ruleset.weapons,
            weapon.proficiency == :unread,
            do: {id, MapSet.member?(gate, id)}
      end

      offered = for {id, true} <- unread.(siala), do: id
      assert offered == []

      # Положительный контроль номер один: записи с непрочитанным владением
      # на Сиале ЕСТЬ — проверка про ворота, а не про пустой список.
      assert unread.(siala) |> Enum.map(&elem(&1, 0)) |> Enum.sort() ==
               [:bite_item, :claw_item, :creature_weapon, :gore_item, :slam_item]

      # Положительный контроль номер два: у ванили механизм жив и кусает —
      # там предлагаемого оружия с непрочитанным владением полно.
      assert unread.(vanilla) |> Enum.count(&elem(&1, 1)) > 0
    end

    test "посох не требует владения, и это записано значением", %{raw: raw} do
      staff = Map.fetch!(weapons(raw), "magic_staff")

      assert staff["proficiency_required"] == false
      assert staff["siala_proficiency_group"] == "no_proficiency_required"
      assert staff["siala_proficiency_group_status"] == "verified"

      # Положительный контроль: у обычного оружия владение требуется, то есть
      # поле различает состояния, а не всегда false.
      assert Map.fetch!(weapons(raw), "longsword")["proficiency_required"] == true
    end
  end

  describe "сиальская таксономия — наша, и это видно" do
    test "файл говорит это прямо, а не подразумевает", %{raw: raw} do
      assert raw["_siala_proficiency"]["taxonomy_correspondence_is_ours"] == true
    end

    # ⚠️ Числовая сверка, которую просил координатор. Она держится в mix-задаче
    # (прогон падает при расхождении), а здесь пришпилена как факт данных.
    test "у каждой группы наше число равно числу с сиальской страницы", %{raw: raw} do
      groups = raw["_siala_proficiency"]["groups"]

      for {name, group} <- groups, group["siala_feat"] do
        assert group["weapons_assigned"] == group["weapons_siala_lists"],
               "#{name}: назначено #{group["weapons_assigned"]}, Сиала перечисляет #{group["weapons_siala_lists"]}"
      end

      # Положительный контроль: групп с фитом действительно пять, то есть цикл
      # выше не прошёл по пустому списку.
      assert Enum.count(groups, fn {_name, group} -> group["siala_feat"] end) == 5
    end

    # 🔴 И вот из-за чего равные числа НЕ значат совпадения таксономий: у топоров
    # они равны, а состав разный. Фандомная группировка записана рядом именно
    # затем, чтобы это было видно из данных.
    test "равный счёт у топоров не значит совпадения — расхождение записано", %{raw: raw} do
      axe = raw["_siala_proficiency"]["groups"]["axe"]

      assert axe["weapons_assigned"] == 6
      assert axe["weapons_in_fandom_category"] == 6

      # А состав другой: серп и кама у Сиалы топоры, у Fandom — клинковое.
      for id <- ~w(sickle kama) do
        weapon = Map.fetch!(weapons(raw), id)
        assert weapon["siala_proficiency_group"] == "axe"
        assert "Category:Bladed weapons" in weapon["categories"]
        assert weapon["siala_proficiency_group_note"] =~ "Fandom"
      end
    end

    test "четыре группы из пяти расходятся с фандомными по счёту", %{raw: raw} do
      groups = raw["_siala_proficiency"]["groups"]

      differing =
        for {name, g} <- groups,
            g["fandom_category"],
            g["weapons_assigned"] != g["weapons_in_fandom_category"],
            do: name

      assert Enum.sort(differing) == ["blade", "hammer", "polearm"]

      # Дальний бой — единственная группа, где две системы сходятся и по счёту,
      # и по составу. ⚠️ Здесь стояло «именно поэтому только у неё статус
      # `verified`» — устарело 16.08.2026: `verified` теперь у всех пяти, просто
      # у дальнего боя довод свой (таксономии совпали сами), а у остальных
      # четырёх — сверка Dan. Совпадение никуда не делось и остаётся под тестом.
      assert groups["ranged"]["weapons_assigned"] ==
               groups["ranged"]["weapons_in_fandom_category"]
    end

    test "статус стоит у каждой записи, а не флагом на файл", %{raw: raw} do
      counts =
        raw["weapons"]
        |> Enum.frequencies_by(& &1["siala_proficiency_group_status"])

      # ⚠️ Было 31 / 9 / 7, потом 31 / 11 / 5 (наблюдение Dan 16.08.2026 перевело
      # дубину и рукопашный удар из `unknown` в `verified`). В тот же день
      # `assumed` кончился совсем: Dan сверил ПЕРЕВОД ИМЁН («Я глянул, вроде
      # перевод подходит»), а группу Сиала называла сама всё это время — пятью
      # страницами фитов и колонкой «Тип оружия» сводной таблицы.
      #
      # ⚠️ Пустого `assumed` в ожидании не пишем: `Enum.frequencies_by/2` ключа
      # без вхождений не заводит, и `"assumed" => 0` уронил бы тест на ровном
      # месте. Отсутствие ключа И ЕСТЬ утверждение «допущений не осталось».
      assert counts == %{"verified" => 42, "unknown" => 5}

      # `unknown` обязан идти с пустой группой, а не с назначенной втихую.
      for weapon <- raw["weapons"], weapon["siala_proficiency_group_status"] == "unknown" do
        assert is_nil(weapon["siala_proficiency_group"]), weapon["id"]
        assert is_binary(weapon["siala_proficiency_group_note"]), weapon["id"]
      end
    end

    # ✅ **Дубина была находкой, и находка закрылась наблюдением** (Dan,
    # 16.08.2026): Сиала не называет её ни в одной из пяти категорий, и это
    # молчание год читалось как «требование не прочитано». В игре дубина
    # доступна всем без фита — то есть молчание источника означало «не нужно»,
    # а не «неизвестно».
    #
    # ⚠️ Заметка про «NONE of its five» ОСТАЁТСЯ в записи: она объясняет,
    # почему поле так долго было пустым, и без неё следующий читатель решит,
    # что группу просто забыли назначить.
    test "дубина: владения не требует, а причина пустой группы записана", %{raw: raw} do
      club = Map.fetch!(weapons(raw), "club")

      assert club["siala_proficiency_group"] == "no_proficiency_required"
      assert club["siala_proficiency_group_status"] == "verified"
      assert club["siala_proficiency_group_note"] =~ "NONE of its five"
      assert club["siala_proficiency_group_note"] =~ "16.08.2026"
    end
  end

  describe "хват и размер" do
    # ⚠️ Хват НЕ поле, и это решение, а не пропуск: он функция размера оружия
    # И размера владельца. Столбец `hands` был бы неверен для карликов.
    test "поля хвата нет ни у одной записи", %{raw: raw} do
      for weapon <- raw["weapons"] do
        refute Map.has_key?(weapon, "hands"), weapon["id"]
        refute Map.has_key?(weapon, "two_handed"), weapon["id"]
      end
    end

    test "зато есть размер и правило с цитатой", %{raw: raw} do
      assert Map.fetch!(weapons(raw), "greatsword")["size"] == "large"
      assert Map.fetch!(weapons(raw), "longsword")["size"] == "medium"

      grip = raw["_grip"]
      assert grip["two_handed_when"] =~ "one category larger"
      assert grip["quotes"]["two_handed"] =~ "one category larger than its wielder"
      assert is_integer(grip["quotes"]["two_handed_source"]["revid"])
      assert grip["player_character_sizes"]["small"] =~ "halfling"
    end

    test "дальнобойность взята из категории, включая подкатегорию метательного", %{raw: raw} do
      by_id = weapons(raw)

      # Лук лежит в `Category:Ranged weapons` прямо.
      assert Map.fetch!(by_id, "longbow")["ranged"] == true

      # ⚠️ А дротик — только в `Category:Throwing weapons`, которая ПОДкатегория
      # дальнобойной. Своя страница дротика слово «ranged» не произносит вовсе,
      # и без чтения дерева категорий он молча стал бы ближним боем.
      dart = Map.fetch!(by_id, "dart")
      assert dart["ranged"] == true
      assert dart["thrown"] == true
      refute "Category:Ranged weapons" in dart["categories"]

      # Положительный контроль: ближний бой действительно не помечен.
      assert Map.fetch!(by_id, "longsword")["ranged"] == false
    end
  end

  describe "противоречия зафиксированы, а не решены" do
    # Два оружия, у которых параметр `proficiency` и категория страницы говорят
    # разное. Выбрать сторону — ровно то, что CLAUDE.md §3 запрещает.
    test "лэнс и посох несут конфликт обоими значениями", %{raw: raw} do
      by_id = weapons(raw)

      for id <- ~w(lance magic_staff) do
        weapon = Map.fetch!(by_id, id)

        assert weapon["status"] == "conflict"
        assert [conflict] = weapon["conflicts"]
        assert conflict["field"] == "proficiency_category"
        assert is_nil(conflict["from_parameter"])
        assert conflict["from_categories"] == "simple"

        # Оба значения на месте, включая сырое — иначе «конфликт» нечем перечитать.
        assert conflict["parameter_raw"] =~ "none"
      end
    end

    # ⚠️ Было 45 — стало 44 задачей 3.40: `trident` получил третий вид
    # конфликта (`siala_grip`, две страницы Сиалы расходятся), непохожий на
    # проф-конфликты лэнса и посоха. Свой тест — в «хват Сиалы» ниже.
    test "у остальных 44 конфликтов нет", %{raw: raw} do
      clean = for w <- raw["weapons"], w["status"] == "parsed", do: w["id"]
      assert length(clean) == 44
    end
  end

  describe "хват Сиалы (siala_grip, задача 3.40)" do
    # `Система оружия` называет хват для персонажа обычного размера — 38 из 47.
    # 9 отсутствующих — не пробел, а находка: страница их просто не перечисляет.
    # ⚠️ Было 29/9 — стало 28/10 (16.08.2026): трезубец переехал из `assumed`
    # в `verified`, когда Dan разрешил его конфликт наблюдением (кейс R1).
    # Число не «поехало» — оно сдвинулось ровно на одну запись и ровно
    # в ту сторону, в какую разрешение и должно двигать статус.
    test "статусы: 28 assumed, 10 verified, 9 без записи (отсутствие в таблице)", %{raw: raw} do
      counts = Enum.frequencies_by(raw["weapons"], & &1["siala_grip_status"])
      assert counts == %{"assumed" => 28, "verified" => 10, nil => 9}
    end

    # 🔴 Проверка догадки Dan (16.08.2026): «похоже что всё древковое оружие
    # двуручное?» — да, 8 из 8, и это второй структурный довод за то, что
    # трезубец двуручный (первый — его `size: large`). Тест держит оба:
    # одноручное древковое стало бы исключением сразу в двух правилах.
    test "вся древковая группа двуручная или двусторонняя, и вся large", %{raw: raw} do
      polearms =
        for w <- raw["weapons"], w["siala_proficiency_group"] == "polearm", do: w

      assert length(polearms) == 8

      for w <- polearms do
        assert w["size"] == "large", "#{w["id"]}: древковое, а размер #{w["size"]}"

        assert w["siala_grip"] in ["two_handed", "double_sided"],
               "#{w["id"]}: древковое, а хват #{w["siala_grip"]}"
      end
    end

    test "verified несёт цитату английского имени с этой же страницы", %{raw: raw} do
      halberd = Map.fetch!(weapons(raw), "halberd")

      assert halberd["siala_grip"] == "two_handed"
      assert halberd["siala_grip_raw"] == "двуручное"
      assert halberd["siala_grip_status"] == "verified"
      assert halberd["siala_grip_note"] =~ "Halberd"
    end

    test "assumed — обычная запись, без обязательной заметки", %{raw: raw} do
      katana = Map.fetch!(weapons(raw), "katana")

      assert katana["siala_grip"] == "one_handed"
      assert katana["siala_grip_raw"] == "одноручное"
      assert katana["siala_grip_status"] == "assumed"
    end

    test "двустороннее совпадает с уже существующим double_sided: true", %{raw: raw} do
      for id <- ~w(dire_mace double_axe two_bladed_sword) do
        weapon = Map.fetch!(weapons(raw), id)
        assert weapon["siala_grip"] == "double_sided", id
        assert weapon["double_sided"] == true, id
      end
    end

    # Вторая половина составной ячейки (`двуручное/метательное`) не стала полем:
    # она равна уже существующим ranged/thrown. Сырое значение при этом цело.
    test "вторая половина составной ячейки не потерялась — она в siala_grip_raw", %{raw: raw} do
      by_id = weapons(raw)

      shuriken = Map.fetch!(by_id, "shuriken")
      assert shuriken["siala_grip"] == "two_handed"
      assert shuriken["siala_grip_raw"] == "двуручное/метательное"
      assert shuriken["ranged"] == true
      assert shuriken["thrown"] == true

      shortbow = Map.fetch!(by_id, "shortbow")
      assert shortbow["siala_grip_raw"] == "двуручное/стрелковое"
      assert shortbow["ranged"] == true
      assert shortbow["thrown"] == false

      sling = Map.fetch!(by_id, "sling")
      assert sling["siala_grip"] == "one_handed"
      assert sling["siala_grip_raw"] == "одноручное/метательное"
      assert sling["ranged"] == true
      assert sling["thrown"] == true
    end

    # Девять не на странице вовсе — creature-оружие, дубина, лэнс, посох, кулак.
    test "девять отсутствующих названы с причиной, не додуманы", %{raw: raw} do
      by_id = weapons(raw)

      for id <- ~w(bite_item claw_item gore_item slam_item creature_weapon club lance
                   magic_staff unarmed_strike) do
        weapon = Map.fetch!(by_id, id)
        assert is_nil(weapon["siala_grip"]), id
        assert is_nil(weapon["siala_grip_raw"]), id
        assert is_nil(weapon["siala_grip_status"]), id
        assert is_binary(weapon["siala_grip_note"]), id
      end

      # Положительный контроль на путаницу «Посохи» (quarterstaff) ↔ «Магические
      # посохи» (magic_staff, без фита вовсе) — они не одно и то же оружие.
      assert Map.fetch!(by_id, "quarterstaff")["siala_grip"] == "two_handed"
      assert Map.fetch!(by_id, "magic_staff")["siala_grip_note"] =~ "quarterstaff"
    end

    # 🔴 Найдено задачей 3.40, не выдумано: `Система оружия` и «Владение
    # древковым оружием» расходятся про трезубец. CLAUDE.md §3 запрещает
    # выбирать сторону — обе стороны зафиксированы.
    #
    # ✅ **РАЗРЕШЁН Dan 16.08.2026 в пользу таблицы** (кейс R1): «отмена моего
    # предыдущего высказывания о размере, оставляем трезубец двуручным».
    #
    # ⚠️ **Ответ был дан дважды и первый раз ОБРАТНЫЙ** — сперва «одноручный,
    # можно вносить как факт», и значение записывалось так. Отзыв пришёл в тот
    # же день, когда Dan перечитал таблицу сам. История записана в парсере
    # (`@siala_grip_resolved`) и стёрта не будет: без неё следующий читатель
    # решит, что вопрос никогда не колебался.
    #
    # ⚠️ **Отзыв подтверждается данными дважды, и оба довода структурные:**
    # трезубец `size: large`, а `large` во всём справочнике даёт двуручное или
    # двустороннее (одноручным он был бы единственным исключением); и вся
    # древковая группа — 8 из 8 — двуручная либо двусторонняя. Ошибается
    # страница фита, а не таблица.
    #
    # ⚠️ Запись остаётся явной, хотя совпала со значением таблицы: она говорит,
    # что конфликт РЕШЁН человеком, а не что его нет.
    test "трезубец — конфликт двух страниц Сиалы, разрешённый в пользу таблицы", %{
      raw: raw
    } do
      trident = Map.fetch!(weapons(raw), "trident")

      assert trident["status"] == "conflict"
      assert trident["siala_grip"] == "two_handed"
      assert trident["siala_grip_status"] == "verified"
      assert trident["siala_grip_raw"] == "двуручное"
      assert trident["siala_grip_note"] =~ "Конфликт"
      assert trident["siala_grip_note"] =~ "РАЗРЕШЁН НАБЛЮДЕНИЕМ"
      assert trident["size"] == "large"

      assert [conflict] = trident["conflicts"]
      assert conflict["field"] == "siala_grip"
      assert conflict["from_parameter"] == "двуручное"
      assert conflict["from_categories"] == "одноручное"
      assert is_binary(conflict["note"])
    end

    test "_siala_grip называет источник и знает о своём единственном конфликте", %{raw: raw} do
      block = raw["_siala_grip"]

      assert block["source"]["wiki"] == "siala"
      assert block["source"]["page"] == "Система оружия"
      assert block["source"]["revid"] == 20527
      assert block["status_counts"] == %{"assumed" => 28, "verified" => 10, "absent" => 9}
      assert block["conflicts_with_proficiency_pages"] == ["trident"]
    end

    # Старый факт (правило, не значение) не должен молчать о новом соседе —
    # иначе читатель `_grip` не узнает, что `_siala_grip` вообще существует.
    test "_grip ссылается на _siala_grip, а не наоборот замалчивает его", %{raw: raw} do
      assert raw["_grip"]["_note"] =~ "_siala_grip"
    end
  end

  describe "грязные значения не приводятся к числам" do
    # ⚠️ Тот же запрет, на котором обожглись уровни заклинаний: `varies`, `0`
    # и «1d2 (small creature) or 1d3 (medium creature)» — не числа, и превращать
    # их в правдоподобные значило бы выдумывать.
    test "непарсящийся урон остаётся сырым, а не округляется", %{raw: raw} do
      by_id = weapons(raw)

      for id <- ~w(creature_weapon unarmed_strike bite_item) do
        weapon = Map.fetch!(by_id, id)
        assert is_nil(weapon["damage"]), id
        assert is_binary(weapon["damage_raw"]), id
      end

      # Двусторонний урон `1d8/1d8` тоже не парсится: взять половину значило бы
      # уполовинить оружие молча.
      dire = Map.fetch!(by_id, "dire_mace")
      assert dire["damage_raw"] == "1d8/1d8"
      assert is_nil(dire["damage"])
      assert dire["double_sided"] == true

      # Положительный контроль: чистое значение разобрано.
      assert Map.fetch!(by_id, "greatsword")["damage"] == %{"count" => 2, "faces" => 6}
    end

    # Зачёркнутая история патчей срезается — тем же правилом, что у заклинаний.
    # У копья-лэнса написано `<del>x1</del> ''x3''`, и без среза оно стало бы
    # оружием с множителем ×1.
    test "у лэнса читается x3, а не зачёркнутый x1", %{raw: raw} do
      lance = Map.fetch!(weapons(raw), "lance")

      assert lance["critical_raw"] == "<del>x1</del> ''x3''"
      assert lance["critical_multiplier"] == 3
    end

    # ⚠️ Диапазон крита пишется не всегда, и его отсутствие НЕ читается как 20:
    # часть страниц пишет `20/x2` явно, часть опускает, значит это
    # непоследовательность вики, а не соглашение.
    test "не названный диапазон крита остаётся null", %{raw: raw} do
      by_id = weapons(raw)

      battleaxe = Map.fetch!(by_id, "battleaxe")
      assert battleaxe["critical_raw"] == "x3"
      assert is_nil(battleaxe["threat_range_low"])
      assert battleaxe["critical_multiplier"] == 3

      # Положительный контроль: где диапазон назван, он прочитан.
      dagger = Map.fetch!(by_id, "dagger")
      assert dagger["threat_range_low"] == 19
      assert dagger["threat_range_high"] == 20
    end
  end

  # 🔴 Замер AC6 (Dan, 26.08.2026): на Сиале варианта `Weapon focus (Creature
  # weapon)` нет вовсе. Закрыт он ВОРОТАМИ ДОМЕНА — тем же механизмом, которым
  # ваниль уже отбивает посох и лэнс, — а список закрытых лежит в сиальской
  # секции `overrides.json` (`weapons.no_feat_variant`).
  #
  # ⚠️ Здесь проверяется МЕХАНИЗМ и его сторожа, на порченых копиях `priv/rules`.
  # Живая запись проверена выше, против живого ruleset'а; контроль на живой
  # записи назавтра получает другое значение и молча перестаёт что-либо
  # проверять (урок 3.85: так за неделю сгорели пять подряд).
  # ---------------------------------------------------------------------------
  # `_off_hand` — ТРЕТИЙ факт файла о руках, задача 3.142.
  #
  # `_grip` отвечает «сколькими руками держат» (функция двух размеров),
  # `_siala_grip` — «что об этом говорит колонка Сиалы», а этот блок — «в какой
  # руке оружие вообще может оказаться», и ключуется он СВОЙСТВОМ, а не
  # размером. Источник — `fandom:Ranged weapon` (revid 70660), в кэше.
  describe "запрет второй руки — блок `_off_hand`" do
    @off_hand_page "priv/wiki_cache/fandom/Ranged weapon.wikitext"

    # 🔴 Цитата сверяется со снапшотом страницы, а не переписана глазами: ровно
    # так же, как база AC сверяется с таблицей у надетого. Обе половины правила
    # живут в ОДНОМ предложении, и обрезать его посередине нельзя — вторая
    # половина и есть то, чего мы не проверяли.
    test "цитата стоит на странице дословно", %{raw: raw} do
      page = File.read!(Path.join(File.cwd!(), @off_hand_page))
      block = raw["_off_hand"]

      assert String.contains?(page, block["quotes"]["rule"])
      assert String.contains?(page, block["quotes"]["gloss"])
      assert block["quotes"]["source"]["page"] == "Ranged weapon"
      assert block["quotes"]["source"]["revid"] == 70_660
    end

    # ⚠️ Слово источника, а не наше обобщение: «any **weapon**». У соседнего
    # правила про двуручное оружие та же вики пишет «anything in the off-hand
    # slot», и вся разница между ними — щит лучника.
    test "занятие названо одно, и это оружие", %{raw: raw} do
      assert raw["_off_hand"]["bars_from_off_hand"] == ["weapon"]
      assert raw["_off_hand"]["barred_from_off_hand"] == true
      assert raw["_off_hand"]["property"] == "ranged"
    end

    # ⚠️ Проверяется у ЯДРА через ruleset, а не чтением JSON: смысл в том, что
    # значение доезжает до расчёта, и доезжает до ОБОИХ ruleset'ов — файл общий.
    test "правило доезжает до обоих ruleset'ов", %{siala: siala, vanilla: vanilla} do
      for ruleset <- [siala, vanilla] do
        rule = Rules.Wield.rules(ruleset).off_hand

        assert rule.field == :ranged?
        assert rule.barred? == true
        assert MapSet.to_list(rule.bars) == [:weapon]
      end
    end
  end

  describe "загрузчик роняет сборку на битом `_off_hand`" do
    setup do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    defp patch_off_hand(root, fun) do
      path = Path.join([root, "vanilla", "weapons.json"])

      path
      |> File.read!()
      |> Jason.decode!()
      |> then(&Map.put(&1, "_off_hand", fun.(&1["_off_hand"])))
      |> Jason.encode!()
      |> then(&File.write!(path, &1))
    end

    # 🔴 ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ ко всем падениям ниже: нетронутая копия обязана
    # грузиться, иначе `assert_raise` зеленел бы на копии, которая не грузится
    # вовсе.
    test "нетронутая копия грузится", %{root: root} do
      assert Loader.load!(root)["siala_41"].wield.off_hand.field == :ranged?
    end

    # ⚠️ И обратная сторона того же контроля: блока нет вовсе — сборка проходит,
    # а правило не запрещает ничего. Полнота лестницы размеров этого блока
    # не касается, у него свой источник и свой сторож.
    test "без блока сборка проходит, и запрета нет", %{root: root} do
      path = Path.join([root, "vanilla", "weapons.json"])

      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.delete("_off_hand")
      |> Jason.encode!()
      |> then(&File.write!(path, &1))

      ruleset = Loader.load!(root)["siala_41"]

      assert ruleset.wield.off_hand == nil
      refute Rules.Wield.barred_from_off_hand?(:sling, ruleset)
      assert ruleset.wield.size_order == [:tiny, :small, :medium, :large]
    end

    # 🔴 Главный сторож: занятие, которое ядро вне второй руки удержать
    # не умеет. Иначе снапшот объявил бы запрет, который молча никогда
    # не сработает, — и щит лучника мы бы «запретили» ничего не сделав.
    test "занятие, которого ядро не удержит", %{root: root} do
      patch_off_hand(root, &Map.put(&1, "bars_from_off_hand", ["weapon", "worn"]))

      assert_raise RuntimeError, ~r/\[:worn\].*never fire/s, fn -> Loader.load!(root) end
    end

    test "свойство, которого ядро не прочитает с оружия", %{root: root} do
      patch_off_hand(root, &Map.put(&1, "property", "shiny"))

      assert_raise RuntimeError, ~r/_off_hand.property.*never fire/s, fn -> Loader.load!(root) end
    end

    test "правило без свойства", %{root: root} do
      patch_off_hand(root, &Map.delete(&1, "property"))

      assert_raise RuntimeError, ~r/no `property`/, fn -> Loader.load!(root) end
    end

    # «Не сказано» среди ответов нет: обе половины правила источник называет
    # отдельно, и умолчание за него приняло бы решение молча.
    test "половина правила без ответа", %{root: root} do
      patch_off_hand(root, &Map.delete(&1, "barred_from_off_hand"))

      assert_raise RuntimeError, ~r/not stated/, fn -> Loader.load!(root) end
    end
  end

  describe "вариант фита, которого на шарде нет" do
    setup do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    # 🔴 ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ НА САМО ПРАВИЛО: умолчание возвращается САМО.
    # Убрать блок — значение снова в предложении, потому что закрывать его
    # будет некому. Ничего не выключено флагом.
    test "без записи значение снова предлагается", %{root: root} do
      patch_overrides(root, &Map.delete(&1["weapons"], "no_feat_variant"))

      ruleset = Loader.load!(root)["siala_41"]
      gate = Map.fetch!(ruleset.choice_domains[:weapon].flags, @gate)

      assert MapSet.member?(gate, :creature_weapon)
      assert MapSet.size(gate) == 41
    end

    # Запись, которой нечего закрыть, роняет сборку. Тихий no-op здесь — это
    # запись, выглядящая применённой: либо справочник переехал под ней, либо
    # значение и так уже вне ворот.
    test "значение, которого ворота и так не открывают, роняет сборку", %{root: root} do
      patch_overrides(root, &put_in(&1["weapons"]["no_feat_variant"]["values"], ["lance"]))

      assert_raise RuntimeError, ~r/does not open in the first place/, fn ->
        Loader.load!(root)
      end
    end

    # Та же ветка с другого конца: шард не может лишиться варианта, которого
    # ваниль никогда не знала.
    test "значение вне справочника роняет сборку", %{root: root} do
      patch_overrides(
        root,
        &put_in(&1["weapons"]["no_feat_variant"]["values"], ["bec_de_corbin"])
      )

      assert_raise RuntimeError, ~r/does not carry it/, fn -> Loader.load!(root) end
    end

    test "домен, которого нет, роняет сборку", %{root: root} do
      patch_overrides(root, &put_in(&1["weapons"]["no_feat_variant"]["domain"], "wepon"))

      assert_raise RuntimeError, ~r/which no dictionary answers/, fn -> Loader.load!(root) end
    end

    # ⚠️ Домен БЕЗ ворот — не «нечего сужать», а «открыто всё»: у `skill`
    # словарь резолвится в сам ruleset, и `flags` там пуст. Запись, положенная
    # туда, не сделала бы ничего и выглядела бы применённой.
    test "домен без ворот роняет сборку", %{root: root} do
      patch_overrides(root, fn overrides ->
        overrides["weapons"]["no_feat_variant"]
        |> Map.merge(%{"domain" => "skill", "values" => ["ride"]})
        |> then(&put_in(overrides["weapons"]["no_feat_variant"], &1))
      end)

      assert_raise RuntimeError, ~r/states no `selectable` gate at all/, fn ->
        Loader.load!(root)
      end
    end

    # Запись УБИРАЕТ у игрока строку, то есть двигает ответ в сторону отказа,
    # а догадка в эту сторону — ложная нелегальность, обойти которую изнутри
    # инструмента нельзя. Поэтому только `verified` и только с цитатой.
    test "невыверенная запись и запись без цитаты роняют сборку", %{root: root} do
      patch_overrides(root, &put_in(&1["weapons"]["no_feat_variant"]["status"], "unclear"))
      assert_raise RuntimeError, ~r/verified/, fn -> Loader.load!(root) end

      patch_overrides(root, &put_in(&1["weapons"]["no_feat_variant"]["quote"], ""))
      assert_raise RuntimeError, ~r/verbatim `quote`/, fn -> Loader.load!(root) end
    end

    # 🔴 Именные ворота БЬЮТ домен-широкие — так `Weapon of choice` получает
    # свой более узкий список. Значит именной пропуск поверх закрытого значения
    # вернул бы его одному фиту МОЛЧА, и такого состояния быть не должно:
    # запись говорит «варианта нет», а не «нет у всех, кроме одного».
    test "именной пропуск поверх закрытого значения роняет сборку", %{root: root} do
      path = Path.join([root, "vanilla", "weapons.json"])
      weapons = path |> File.read!() |> Jason.decode!()

      patched =
        update_in(weapons["weapons"], fn list ->
          for weapon <- list do
            if weapon["id"] == "creature_weapon",
              do: Map.put(weapon, "weapon_focus", true),
              else: weapon
          end
        end)

      File.write!(path, Jason.encode!(patched))

      assert_raise RuntimeError, ~r/still name it in their own gate/, fn -> Loader.load!(root) end
    end

    # Отрицательный контроль ко всем сторожам разом: нетронутая копия грузится.
    # Без него любой из них зеленел бы и на сломанной копии `priv/rules`.
    test "нетронутая копия грузится и даёт те же 40", %{root: root} do
      ruleset = Loader.load!(root)["siala_41"]
      gate = Map.fetch!(ruleset.choice_domains[:weapon].flags, @gate)

      assert MapSet.size(gate) == 40
      refute MapSet.member?(gate, :creature_weapon)
    end

    defp patch_overrides(root, fun) do
      path = Path.join([root, "siala_41", "overrides.json"])
      overrides = path |> File.read!() |> Jason.decode!()
      patched = fun.(overrides)

      updated =
        if is_map(patched) and Map.has_key?(patched, "weapons"),
          do: patched,
          else: put_in(overrides["weapons"], patched)

      File.write!(path, Jason.encode!(updated))
    end
  end
end
