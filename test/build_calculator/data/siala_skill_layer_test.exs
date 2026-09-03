defmodule BuildCalculator.Data.SialaSkillLayerTest do
  @moduledoc """
  `priv/rules/siala_41/skills.json` and `systems.json` laid over the vanilla
  dictionary.

  All 29 pages of the shard's «Навыки» category, read by hand: 22 of them changed
  from vanilla. Almost none of it moves a number — what the calculator shows for
  a skill is its ranks — so the value of the layer is mostly that it stops being
  invisible: `alchemy` becomes a skill instead of a dangling reference, each
  change travels on its record, and the two rules that *do* move numbers become
  rules.

  Layering is `vanilla -> siala` exactly as for classes and feats, and the same
  refusal holds: a fact marked `unclear` is a human saying they could not pin the
  value down, and it never becomes a rule.

  `vanilla_baseline` is this layer's own field and answers a question the other
  two never ask: **how do we know** the skill is unchanged. "The page says it
  works as in the original" and "the page never addressed it" look identical
  once collapsed to a boolean, and they are not the same claim.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Skills}

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  describe "the shard's own skill" do
    # source: siala «Alchemy» revid 20550. No vanilla counterpart — the shard
    # added the skill outright, and harper_scout takes it as a class skill.
    test "alchemy exists only in the shard ruleset", %{siala: s, vanilla: v} do
      refute Map.has_key?(v.skills, :alchemy)
      assert %{siala_only?: true, ru: "Alchemy"} = s.skills[:alchemy]
    end

    # 🔴 Здесь стояло «its unstated fields are named, not guessed» с четырьмя
    # именами в `unknown_fields` и `key_ability == nil`: ни одна вики этих полей
    # не называла, а CON из формулы переплавки — не то же самое, что ключевая
    # характеристика навыка. **Dan закрыл три из четырёх одним ответом
    # 17.08.2026** (кейс P1: «ее атрибут - мудрость», «Штрафа нет», «качать
    # на других классах можно, но только кросс-классово»), и правило CLAUDE.md §3
    # тут не отменено, а исполнено: наблюдение в игре стоит ВЫШЕ страницы вики,
    # поэтому молчание вики перестало быть последним словом.
    #
    # ⚠️ 27.08.2026 (задача 3.129) закрыло и четвёртое — сверкой с хаками, не
    # вики и не игроком. `skills.2da`, строка 28: `Untrained=1` → `trained_only:
    # false`. Заголовок теста и его текст были про «три из четырёх», это больше
    # не так, но значение НЕ заведено записью в `changes[]` — намеренно.
    # `trained_only` алхимии по-прежнему не читает ни один модуль `rules/`,
    # и заведение его как факта БЕЗ подходящего получателя в закрытом словаре
    # `_receivers` завело бы НОВЫЙ гэп `{:not_modelled, {:skill_change, :alchemy,
    # "trained_only"}}`, которого не было и не должно появиться (правило
    # «нет affects — значит гэп», `Rules.GapReceivers.ours?/2`). Поэтому
    # значение — только в прозе `note` записи, с цитатой и `source.kind: "hak"`,
    # а `unknown_fields` опустел без встречной записи в `changes[]`.
    test "все четыре поля названы источником, последнее — прозой, а не changes[]", %{siala: s} do
      assert s.skills[:alchemy].key_ability == :wis
      assert s.skills[:alchemy].armor_check_penalty == :none

      # «кросс-классовый для всех, кроме Арфиста» — это `exclusive?: false`
      # плюс единственный класс в `class_skill_for`.
      refute s.skills[:alchemy].exclusive?

      # ⚠ `trained_only` больше не в unknown_fields (закрыт хаками 27.08.2026),
      # но и не заведён в changes[] — см. комментарий выше. `unknown_fields`
      # опустел, а не заменился записью.
      assert s.skills[:alchemy].unknown_fields == []
    end

    # ⚠ Факт с цитатой и «поля не назвал никто» — про одно поле два
    # взаимоисключающих утверждения, и загрузчик обязан падать, а не выбирать
    # молча. Ловится настоящая полуправка: у `armor_check_penalty` список
    # сильнее записи, поэтому забытое имя вернуло бы `:unknown` при прочитанном
    # ответе — «?» на экране вместо числа и ни одного сообщения об этом.
    test "поле, названное и записью, и unknown_fields сразу, роняет сборку" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "skills.json"])
      data = path |> File.read!() |> Jason.decode!()

      contradicted =
        update_in(data["skills"], fn list ->
          for skill <- list do
            if skill["id"] == "alchemy",
              do: Map.put(skill, "unknown_fields", ["trained_only", "armor_check_penalty"]),
              else: skill
          end
        end)

      File.write!(path, Jason.encode!(contradicted))

      assert_raise RuntimeError, ~r/unknown_fields and states the same field/, fn ->
        Loader.load!(root)
      end
    end
  end

  describe "vanilla_baseline distinguishes three states" do
    # source: siala «Скрытность» revid 19465 — «Навык работает как в оригинальной
    # игре.» A statement, and a stronger one than silence.
    test "«works as in the original» is stated outright", %{siala: s} do
      assert %{"value" => true, "status" => "verified"} = s.skills[:hide].vanilla_baseline
    end

    # source: siala «Крафт брони» — «Стандартный крафт доспехов отключен и
    # заменен на сиальский».
    test "«does not» is also stated outright", %{siala: s} do
      assert %{"value" => false} = s.skills[:craft_armor].vanilla_baseline
    end

    # source: siala «Карманные кражи» revid 18248 — the page is entirely about
    # *why* the skill matters on the shard («воровать можно у игроков, и НПС…»)
    # and never says whether the mechanic changed. Vanilla stays an assumption,
    # and `value: null` with `status: "unclear"` is what says so. A `true` here
    # would be a claim nobody made.
    test "and silence is recorded as silence", %{siala: s} do
      assert %{"value" => nil, "status" => "unclear"} = s.skills[:pick_pocket].vanilla_baseline

      # Six pages do not raise the question at all and carry no field — a third
      # state again, and deliberately not merged with the fourth.
      silent = for {id, skill} <- s.skills, is_nil(skill.vanilla_baseline), do: id
      assert Enum.sort(silent) == ~w(alchemy intimidate lore persuade ride taunt)a

      # vanilla has no baseline field at all — there is no shard page to have one
      assert Enum.all?(Map.values(Data.ruleset!("vanilla").skills), &is_nil(&1.vanilla_baseline))
    end
  end

  describe "changes travel, and the ones with no home are named" do
    # source: siala «Верховая езда» revid 19464 — the vanilla dead skill is alive
    # on the shard, with its own formulas. There is no field on a skill record
    # for "alive", so nothing is applied and the fact is reported.
    test "a change with no mechanical home lands in siala_unapplied", %{siala: s} do
      whats = Enum.map(s.skills[:ride].siala_unapplied, & &1["what"])

      assert "enabled" in whats
      assert "mount_bonus_formula" in whats
    end

    test "and the whole page still travels on the record", %{siala: s} do
      assert length(s.skills[:ride].siala_changes) == 4
      assert %{"page" => "Верховая езда", "revid" => 18_255} = s.skills[:ride].siala_source
    end

    # source: siala «Арфист-скаут» revid 19414. Оговорка обязана уйти вместе
    # с тем, как факт стал считаться: CLAUDE.md §6 запрещает продолжать печатать
    # «не можем посчитать» про посчитанное.
    #
    # ⚠️ ПЕРЕПИСАН 16.08.2026 (замер Dan, `GAME_CHECKS.md` F7). Здесь стояло
    # «Bardic Knowledge стал правилом», и правило это строил СЛОЙ НАВЫКОВ:
    # «+уровень Арфиста, начиная со 2-го». Замер показал, что прибавка равна
    # сумме уровней барда и Арфиста, то есть страница шарда описывает половину
    # умения (её вики — дифф, а не справочник). Считать стала ванильная разметка
    # (`vanilla/feat_skill_bonuses.json` → bardic_knowledge), а эта запись
    # помечена `counted_elsewhere`: правил слой из неё больше не строит, зато
    # цитата и revid остались на месте.
    #
    # ⚠️ Применённой при этом она БЫТЬ НЕ ПЕРЕСТАЛА. «Посчитано в другом месте»
    # и «не посчитано» — противоположные утверждения, и уедь запись
    # в `siala_unapplied`, игрок увидел бы оговорку про число, которое у него
    # на экране посчитано.
    test "Bardic Knowledge считается разметкой и оговоркой не стал", %{siala: s} do
      whats = Enum.map(s.skills[:lore].siala_unapplied, & &1["what"])

      refute "harper_bardic_knowledge_bonus" in whats

      # Положительный контроль: остальные изменения Lore по-прежнему числятся
      # неприменёнными, то есть `refute` выше зеленеет не от пустого списка.
      assert "scroll_crafting_check" in whats

      # Правила у слоя больше нет — иначе уровни Арфиста считались бы дважды.
      assert s.skill_rules.class_level_bonuses == []

      # А сама запись со всеми своими полями на месте, и указатель называет,
      # кто её считает вместо слоя.
      change =
        Enum.find(s.skills[:lore].siala_changes, &(&1["what"] == "harper_bardic_knowledge_bonus"))

      assert change["counted_elsewhere"]["record"] == "bardic_knowledge"
      assert change["source"]["revid"] == 19_414
    end

    # The layer is not allowed to *reduce* what is known: every vanilla skill
    # keeps its vanilla facts.
    test "the vanilla record underneath is untouched", %{siala: s, vanilla: v} do
      assert s.skills[:spellcraft].key_ability == v.skills[:spellcraft].key_ability
      assert s.skills[:spellcraft].trained_only? == v.skills[:spellcraft].trained_only?
      assert map_size(s.skills) == map_size(v.skills) + 1
    end
  end

  describe "the two rules that reach a character sheet" do
    # source: fandom «Spellcraft» revid 68572, transcribed machine-readably into
    # overrides.json because vanilla/skills.json holds it only as prose.
    test "the Spellcraft save bonus is a rule in both rulesets", %{siala: s, vanilla: v} do
      for ruleset <- [s, v] do
        assert [%{skill: :spellcraft, bonus: 1, per_ranks: 5}] = ruleset.skill_rules.save_bonus
      end
    end

    # It counts towards the same +20 as equipment (`source: user`) — the field is
    # read from the data, not decided in code.
    test "and it declares which ceiling it counts towards", %{siala: s} do
      assert [%{counts_toward_cap: :saving_throw_bonus}] = s.skill_rules.save_bonus
    end

    # source: siala «Скрытность» revid 19465, «== Мультиклассовость ==», restated
    # word for word on «Тихое передвижение» revid 19466.
    test "the four-class stealth penalty is Siala's alone", %{siala: s, vanilla: v} do
      assert %{
               skills: [:hide, :move_silently],
               classes_in_build: 4,
               penalty_per_level: -1
             } = s.skill_rules.stealth_multiclass_penalty

      assert v.skill_rules.stealth_multiclass_penalty == nil
    end

    test "its profile classes are the eight the page names", %{siala: s} do
      profile = s.skill_rules.stealth_multiclass_penalty.profile_classes

      assert MapSet.size(profile) == 8

      for class <- ~w(assassin rogue bard blackguard druid shadowdancer ranger harper_scout)a do
        assert MapSet.member?(profile, class), "#{class} is on the wiki's list"
      end
    end
  end

  describe "what reaches a build's own gap list" do
    # Scoped to the skills the build actually bought ranks in. A caveat about
    # Ride on a build that never took a rank of it is noise, and a gap list
    # people learn to skim is a gap list that has stopped working (CLAUDE.md §9).
    #
    # ⚠️ Вложиться надо в ДВА навыка сразу — в тот, что отчитывается, и в тот,
    # что молчит: порознь каждая половина зеленела бы и у сломанного фильтра
    # (у молчащего — если фильтр съедает всё, у отчитывающегося — если он
    # не фильтрует вовсе).
    #
    # ⚠️ Отчитывающийся навык здесь менялся ЧЕТЫРЕЖДЫ, и четвёртый раз кончился
    # тем, что отчитывающихся не осталось вовсе. Первые два факт терял нашего
    # получателя:
    #   * `hide` (`affects_spy_birds`) → `summons`, 14.08.2026 (разметка навыков);
    #   * `listen` (`rogue_stealth_penalty`) → `buff`, 17.08.2026 — решение Dan:
    #     «Режим скрытности = считай бафф», то есть временный активируемый
    #     эффект, а не свойство билда (CLAUDE.md §9).
    # Третий — `craft_trap`, 17.08.2026 — факт ПРИМЕНИЛСЯ: замер Dan показал,
    # что классовыми Теневому танцору стали оба навыка ловушек, спора с
    # `classes.json` не было вовсе, и оговорке не о чем говорить.
    # Четвёртый — `set_trap / class_skills_unchanged`, 22.08.2026, задача 3.78:
    # факт применился, но ИНАЧЕ — он не стал правилом, он стал ПРОВЕРКОЙ
    # (см. describe «утверждение „список классов ванильный“» ниже).
    #
    # 🔴 Поэтому положительная половина переехала на СИНТЕТИЧЕСКИЙ ruleset,
    # и это не украшение теста. Живых гэпов у слоя навыков ноль
    # (`GapReceivers.census/1` → `skills.gaps == 0`), а `refute` на мёртвом
    # механизме зеленеет одинаково хорошо и когда механизм жив, и когда его
    # выпилили. Тот же приём, что у `{:missing_data, {:choice_domain, …}}`
    # (CLAUDE.md §6) и у «демоции потолка» ниже в этом же файле: правило,
    # у которого кончились носители, держится копией `priv/rules` с намеренно
    # испорченной записью.
    test "молчащие навыки молчат, и молчат они по разметке", %{siala: ruleset} do
      build =
        BuildCalculator.Rules.Build.new(
          levels: List.duplicate(:rogue, 10),
          skills: %{1 => %{hide: 4, listen: 4, set_trap: 4}}
        )

      gaps = BuildCalculator.Rules.compute(build, ruleset).gaps

      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :hide, _}}, &1))
      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :ride, _}}, &1))

      # Само решение Dan от 17.08.2026, проверенное со стороны билда: вор
      # с рангами в Слухе и Обнаружении про штраф в режиме скрытности молчит.
      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :listen, _}}, &1))
      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :spot, _}}, &1))

      # ...и `set_trap` тоже молчит — но по ТРЕТЬЕЙ причине, отличной от обеих
      # выше: факт не отфильтрован получателем и не обойдён, он сверен.
      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :set_trap, _}}, &1))
    end

    # Положительная половина: механизм доставки жив, и первый же неприменённый
    # факт с нашим получателем по нему поедет. Демотируется `set_trap /
    # class_skills_unchanged` — то есть проверяется заодно, что отказ от
    # `unclear` СИЛЬНЕЕ новой клаузы: запись, которую человек не смог прочитать
    # однозначно, не сверяется и правилом не становится, как бы она ни
    # выглядела (`apply_skill_change/3`, первая клауза).
    #
    # ⚠️ Вложиться надо в ДВА навыка сразу — в тот, что отчитывается, и в тот,
    # что молчит: порознь каждая половина зеленела бы и у сломанного фильтра
    # (у молчащего — если фильтр съедает всё, у отчитывающегося — если он
    # не фильтрует вовсе).
    test "демоция факта навыка до unclear возвращает его оговорку" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "skills.json"])
      data = path |> File.read!() |> Jason.decode!()

      demoted =
        update_in(data["skills"], fn list ->
          for skill <- list do
            if skill["id"] == "set_trap" do
              update_in(skill["changes"], fn changes ->
                for change <- changes do
                  if change["what"] == "class_skills_unchanged",
                    do: Map.put(change, "status", "unclear"),
                    else: change
                end
              end)
            else
              skill
            end
          end
        end)

      File.write!(path, Jason.encode!(demoted))
      ruleset = Loader.load!(root)["siala_41"]

      build =
        Build.new(
          levels: List.duplicate(:rogue, 10),
          skills: %{1 => %{hide: 4, set_trap: 4}}
        )

      gaps = Rules.compute(build, ruleset).gaps

      assert {:not_modelled, {:skill_change, :set_trap, "class_skills_unchanged"}} in gaps
      assert {:not_modelled, {:skill_change, :set_trap, "class_skills_unchanged"}} in ruleset.gaps

      # ...а сосед по билду по-прежнему молчит — фильтр получателей работает,
      # а не выключился заодно.
      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :hide, _}}, &1))
    end

    # ⚠️ Вторая половина того же замера, и без неё первая половину правды:
    # `craft_trap` пропал из оговорок не потому, что его отфильтровали
    # получателем, а потому, что он ПОСЧИТАН. Разница видна только так —
    # молчание у этих двух причин одинаковое.
    test "про craft_trap оговорки нет, и это потому, что он применён",
         %{siala: ruleset} do
      build =
        BuildCalculator.Rules.Build.new(
          levels: List.duplicate(:rogue, 10) ++ List.duplicate(:shadowdancer, 10),
          skills: %{1 => %{craft_trap: 4}}
        )

      gaps = BuildCalculator.Rules.compute(build, ruleset).gaps

      refute Enum.any?(gaps, &match?({:not_modelled, {:skill_change, :craft_trap, _}}, &1))

      # Положительный контроль: факт не потерян, он именно применён — навык
      # стал классовым Теневому танцору, чего в ванили нет.
      assert MapSet.member?(ruleset.classes[:shadowdancer].class_skills, :craft_trap)

      # ...и `class_skills` ушёл именно из НЕПРИМЕНЁННЫХ, а не из данных: два
      # оставшихся факта навыка (сиальское применение и польза друидам) на
      # месте и по-прежнему неприменены — просто оба не про наши числа.
      assert ruleset.skills[:craft_trap].siala_unapplied |> Enum.map(& &1["what"]) ==
               ["use", "used_by_druid_phantoms"]
    end

    # 🔴 Здесь стояло «a skill with no key ability says so, and only once»:
    # у Алхимии характеристики не было, гэп про неё печатался, и вся тонкость
    # была в том, чтобы он печатался ОДИН раз — метка `special_ability` у самой
    # записи существовала ровно затем, чтобы неприменённый факт не задваивал
    # более точную оговорку `Skills.value/4`.
    #
    # **Замер Dan 17.08.2026 (кейс P1) снял обе строки сразу**, и кейс
    # перевёрнут в тишину: факт применён, значит гэпа нет ни в одной из двух
    # форм. Задваивать теперь нечего — но проверять надо по-прежнему обе, иначе
    # «применили и заодно потеряли» выглядело бы так же зелено.
    test "у Алхимии не осталось ни одной из двух прежних оговорок", %{siala: ruleset} do
      build =
        BuildCalculator.Rules.Build.new(
          levels: List.duplicate(:harper_scout, 5),
          base_abilities: %{str: 10, dex: 10, con: 10, int: 10, wis: 14, cha: 10},
          skills: %{1 => %{alchemy: 4}}
        )

      stats = BuildCalculator.Rules.compute(build, ruleset)

      refute {:missing_data, {:skill_key_ability, :alchemy}} in stats.gaps
      refute {:not_modelled, {:skill_change, :alchemy, "key_ability"}} in stats.gaps

      # Положительный контроль: тишина оттого, что число ПОСЧИТАНО, а не оттого,
      # что навык выпал из расчёта вовсе.
      assert stats.skill_values[:alchemy].total == 4 + 2
    end

    # The Spellcraft scope is reported once, by the gap that states it precisely,
    # and not a second time as a generic "change not applied".
    test "the Spellcraft scope is not reported twice", %{siala: ruleset} do
      build =
        BuildCalculator.Rules.Build.new(
          levels: List.duplicate(:wizard, 20),
          skills: %{20 => %{spellcraft: 20}}
        )

      gaps = BuildCalculator.Rules.compute(build, ruleset).gaps

      assert {:not_modelled, {:save_bonus_scope, :spellcraft}} in gaps
      refute {:not_modelled, {:skill_change, :spellcraft, "save_bonus_scope"}} in gaps
    end
  end

  describe "the shard's custom systems" do
    # source: siala_41/systems.json — ten systems, each with a verdict on whether
    # it belongs in the calculator; the file is read so the decision is visible
    # rather than implied by the absence of code (CLAUDE.md §3).
    #
    # ⚠️ Именно эти строки — то место, где вердикт обязан устаревать ЗАМЕТНО.
    # `sagra_warriors` три волны подряд стояла `no`, хотя с решения Dan
    # 08.08.2026 членство в группе выбирает вариант расового бонуса, то есть
    # меняет AB на три очка. Дальше вердикты проверяются не глазами, а этим
    # тестом: он ловит и обратную правку («вернули no»), и добавление
    # одиннадцатой системы.
    test "all ten arrive with their verdicts", %{siala: s} do
      assert length(s.systems) == 10

      by_id = Map.new(s.systems, &{&1.id, &1.verdict})

      assert by_id[:stat_caps] == "yes"
      assert by_id[:weapon_system] == "partial"
      assert by_id[:mini_sets] == "no"
      assert by_id[:mintra] == "no_data"

      # Обе группы классов — `partial`, и по разным причинам: у Сагры доезжают
      # флажок И выбор варианта расового бонуса, у Адры только флажок.
      # ⚠️ Здесь стояло «что даёт членство, не сказал никто —
      # `what_the_group_gives: null`»: с 25.08.2026 сказал владелец (зелья
      # Адры, `kind: user`), и вики по-прежнему молчит. На вердикт это
      # не влияет — расходники в числа не идут, доезжает всё тот же флажок.
      assert by_id[:sagra_warriors] == "partial"
      assert by_id[:adra_warriors] == "partial"
    end

    # Вердикт `partial` у групп — не прозаическая пометка, а утверждение,
    # проверяемое вызовом: смена ОДНОГО уровня класса меняет и флажок, и число.
    # ⚠️ Обе половины в одном тесте: «9 у сагровика» зеленеет и при варианте,
    # выбранном по чему угодно другому, а «6 у несагровика» — при бонусе,
    # который не считается вовсе.
    test "the verdict `partial` of sagra_warriors is a call, not prose", %{siala: s} do
      # ⚠️ Меч в руках: расовый бонус включается оружием (замер Dan 15.08.2026,
      # `GAME_CHECKS.md` Q1/Q4), и без него обе половины кейса были бы нулями.
      armed =
        BuildCalculator.Rules.Gear.new(weapon: :longsword, feats: [:siala_blade_proficiency])

      pure = Build.new(race: :half_elf, levels: List.duplicate(:fighter, 40), gear: armed)

      mixed =
        Build.new(
          race: :half_elf,
          levels: List.duplicate(:fighter, 39) ++ [:bard],
          gear: armed
        )

      pure_stats = Rules.compute(pure, s)
      mixed_stats = Rules.compute(mixed, s)

      assert :sagra_warriors in Enum.map(pure_stats.class_groups, & &1.id)
      assert pure_stats.racial_bonus.variant == :sagra_warrior
      assert pure_stats.racial_bonus.counted == 9

      assert mixed_stats.class_groups == []
      assert mixed_stats.racial_bonus.variant == :base
      assert mixed_stats.racial_bonus.counted == 6
    end

    # `derived_stats_touched` is the price of the decision, stated in the data:
    # mini-sets are worth +15…+91 % hit points in game and the calculator does
    # not model them, which is why its HP will never match a wiki build page.
    test "a system that is out of scope still says what it touches in game", %{siala: s} do
      mini_sets = Enum.find(s.systems, &(&1.id == :mini_sets))

      assert "hp" in mini_sets.derived_stats_touched
      assert "attack_bonus" in mini_sets.derived_stats_touched
    end

    test "vanilla has none of them" do
      assert Data.ruleset!("vanilla").systems == []
    end

    # The one system that does go into the calculator is stated twice — as prose
    # in systems.json and as numbers in overrides.json — and the loader refuses
    # to build if the two ever drift apart.
    test "the ceilings systems.json states are the ceilings the core applies", %{siala: s} do
      stated =
        s.systems
        |> Enum.find(&(&1.id == :stat_caps))
        |> Map.fetch!(:facts)
        |> Map.new(fn fact -> {fact["what"], fact["value"]} end)

      assert stated["attack_bonus_cap"] == s.stat_caps.attack_bonus
      assert stated["skill_bonus_cap"] == s.stat_caps.skill_bonus

      # ...and the fourth, `max_skill_value: 127`, was `unclear` until 03.08.2026
      # and is now `verified` — Dan confirmed it as the general rule, so it is
      # carried like the others and no longer raises a gap.
      #
      # ⚠️ Carried, not biting: nothing the calculator can compute reaches 127
      # before the armoury (a total is bounded around 62 — see `Rules.Skills`).
      # This is the assertion that will notice the day someone reads the absent
      # clip as an absent ceiling and "fixes" the data back.
      assert stated["max_skill_value"] == 127
      assert s.stat_caps.max_skill_value == 127
      refute {:missing_data, {:stat_cap, :max_skill_value}} in s.gaps
    end

    test "a disagreement between the two statements fails the build" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "siala_41"))
      File.mkdir_p!(Path.join(root, "vanilla"))

      for file <- ~w(classes.json epic.json skills.json) do
        File.cp!(Path.join("priv/rules/vanilla", file), Path.join([root, "vanilla", file]))
      end

      for file <- ~w(overrides.json skills.json) do
        File.cp!(Path.join("priv/rules/siala_41", file), Path.join([root, "siala_41", file]))
      end

      on_exit(fn -> File.rm_rf!(root) end)

      systems =
        Jason.encode!(%{
          "systems" => [
            %{
              "id" => "stat_caps",
              "facts" => [%{"what" => "attack_bonus_cap", "value" => 25}]
            }
          ]
        })

      File.write!(Path.join([root, "siala_41", "systems.json"]), systems)

      assert_raise RuntimeError, ~r/disagree/, fn -> Loader.load!(root) end
    end

    # ⚠️ The positive control for every «этого гэпа больше нет» assertion in the
    # suite. As of 03.08.2026 all five ceilings are `verified`, so no ruleset we
    # ship raises a `{:missing_data, {:stat_cap, …}}` gap any more — and a suite
    # full of `refute`s on a mechanism that quietly died would be green from top
    # to bottom. So the status is demoted here, in a copy, and the gap has to
    # come back.
    test "demoting a verified ceiling brings its gap back" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "overrides.json"])
      overrides = path |> File.read!() |> Jason.decode!()

      demoted = put_in(overrides["stat_caps"]["max_skill_value"]["status"], "unclear")
      File.write!(path, Jason.encode!(demoted))

      ruleset = Loader.load!(root)["siala_41"]

      assert {:missing_data, {:stat_cap, :max_skill_value}} in ruleset.gaps
      refute Map.has_key?(ruleset.stat_caps, :max_skill_value)
      # and the ceilings that were not demoted are untouched — the mechanism is
      # per-entry, not all-or-nothing
      assert ruleset.stat_caps.dodge_ac == 20
    end
  end

  # source: siala «Установка ловушки» revid 11494 — «Классы, которые используют
  # данный навык: [[Вор|воры]], [[Рейнджер|рейнджеры]], [[Убийца|убийцы]]»,
  # против `vanilla/skills.json` → `set_trap.classes_raw` = «[[assassin]],
  # [[ranger]], [[rogue]]» (fandom «Set trap» revid 70062).
  #
  # Единственный факт корпуса, утверждающий СОВПАДЕНИЕ, а не изменение
  # (проверено обходом всех `what` во всех файлах `priv/rules`, 22.08.2026 —
  # носитель ровно один). Применять тут нечего, и до задачи 3.78 он ехал
  # к игроку оговоркой «не смоделировано» — про правило, которое на экране
  # посчитано, просто пришло из ванильного файла.
  describe "утверждение «список классов ванильный» сверяется, а не применяется" do
    test "факт применён, и при этом сам факт на месте", %{siala: s} do
      skill = s.skills[:set_trap]

      refute "class_skills_unchanged" in Enum.map(skill.siala_unapplied, & &1["what"])
      assert "class_skills_unchanged" in Enum.map(skill.siala_changes, & &1["what"])

      # ⚠️ Положительный контроль ровно на то, чем эта запись отличается от
      # `craft_trap`: там применение ДОБАВИЛО класс, здесь не изменилось ничто.
      assert skill.class_for == [:assassin, :ranger, :rogue]
    end

    # 🔴 Ловушка, ради которой задача и написана подробно: наивное «сделать
    # классовыми ровно трёх названных» отняло бы навык у Теневого танцора,
    # которого страница не упоминает вовсе. Ошибка была бы тихой и дорогой —
    # цена ранга вдвое, потолок вдвое.
    test "Теневой танцор навык не потерял, хотя страница его не называет",
         %{siala: s, vanilla: v} do
      # Трое названных — из ванили, поэтому и там, и там.
      for class <- [:rogue, :ranger, :assassin] do
        assert MapSet.member?(s.classes[class].class_skills, :set_trap)
        assert MapSet.member?(v.classes[class].class_skills, :set_trap)
      end

      # Четвёртый — только у Сиалы, и приходит он со страницы КЛАССА
      # (`siala_41/classes.json` → shadowdancer), а не с этой.
      assert MapSet.member?(s.classes[:shadowdancer].class_skills, :set_trap)
      refute MapSet.member?(v.classes[:shadowdancer].class_skills, :set_trap)

      # И список не разросся: сверка ничего не добавляет никому.
      holders = for {id, c} <- s.classes, MapSet.member?(c.class_skills, :set_trap), do: id
      assert Enum.sort(holders) == [:assassin, :ranger, :rogue, :shadowdancer]
    end

    # ⚠️ Сверка идёт против ВАНИЛИ, и обе стороны расхождения роняют сборку —
    # но по разным причинам, поэтому и сообщения разные, и проверяются они
    # порознь. Имя, которого в ванили нет, — это шард ДОБАВИЛ класс, и такое
    # обязано быть записано как `class_skills`, иначе билд молча платит
    # кросс-классовую цену под половинным потолком.
    test "имя, которого нет в ванили, роняет сборку как незаписанное добавление" do
      root = tampered_set_trap(["rogue", "ranger", "assassin", "shadowdancer"])

      assert_raise RuntimeError, ~r/shard ADDING a class/, fn -> Loader.load!(root) end
    end

    # Обратная сторона: имя ванили, которого страница не называет. Это либо шард
    # класс УБРАЛ, либо страница неполна (CLAUDE.md §3, урок фита `Artist`:
    # молчание источника — молчание, а не отрицание). Выбрать из двух за человека
    # загрузчик права не имеет — честного числа тут нет ни у одного варианта.
    test "имя ванили, которого страница не называет, тоже роняет сборку" do
      root = tampered_set_trap(["rogue", "ranger"])

      assert_raise RuntimeError, ~r/either a removal or a partial page/, fn ->
        Loader.load!(root)
      end
    end

    # ⚠️ И падает оно ИМЕННО на сверке, а не «где-то в загрузчике»: сообщение
    # называет файл, навык и обе стороны. Отказ без обеих сторон заставил бы
    # редактора идти сравнивать руками ровно то, что машина только что сравнила.
    test "сообщение называет обе стороны расхождения" do
      root = tampered_set_trap(["rogue", "ranger", "assassin", "shadowdancer"])

      error = assert_raise RuntimeError, fn -> Loader.load!(root) end
      message = error.message

      assert message =~ "siala_41/skills.json"
      assert message =~ "set_trap"
      assert message =~ ":shadowdancer"
      assert message =~ "vanilla layer holds"
    end

    # ⚠️ Третья ветка сторожа, и она про НЕСРАВНИМОЕ, а не про расхождение.
    # У Лечения и Знаний в ванили `classes_all`, то есть навык классовый
    # у всех; «список не менялся» с тремя именами против «всех» — это не
    # два разных списка, а список против не-списка, и печатать их диффом
    # значило бы выдать бессмыслицу за расхождение.
    test "«у всех классов» против названного списка — своё сообщение" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "skills.json"])
      data = path |> File.read!() |> Jason.decode!()

      tampered =
        update_in(data["skills"], fn list ->
          for skill <- list do
            if skill["id"] == "heal_skill" do
              Map.update(skill, "changes", [], fn changes ->
                changes ++
                  [
                    %{
                      "what" => "class_skills_unchanged",
                      "affects" => ["skill_points"],
                      "value" => ["rogue", "ranger", "assassin"],
                      "quote" => "синтетика теста",
                      "status" => "verified"
                    }
                  ]
              end)
            else
              skill
            end
          end
        end)

      File.write!(path, Jason.encode!(tampered))

      assert_raise RuntimeError, ~r/gives this skill to every class/, fn ->
        Loader.load!(root)
      end
    end

    defp tampered_set_trap(classes) do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.cp_r!("priv/rules", root)
      on_exit(fn -> File.rm_rf!(root) end)

      path = Path.join([root, "siala_41", "skills.json"])
      data = path |> File.read!() |> Jason.decode!()

      tampered =
        update_in(data["skills"], fn list ->
          for skill <- list do
            if skill["id"] == "set_trap" do
              update_in(skill["changes"], fn changes ->
                for change <- changes do
                  if change["what"] == "class_skills_unchanged",
                    do: Map.put(change, "value", classes),
                    else: change
                end
              end)
            else
              skill
            end
          end
        end)

      File.write!(path, Jason.encode!(tampered))
      root
    end
  end

  describe "a ruleset built without the skill layer" do
    # The file is optional in the same way every other one is: absent means "no
    # rule", never a crash and never a default rule invented in its place.
    test "carries no skill rules and no penalty" do
      root = Path.join(System.tmp_dir!(), "rules_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, "vanilla"))

      for file <- ~w(classes.json epic.json skills.json) do
        File.cp!(Path.join("priv/rules/vanilla", file), Path.join([root, "vanilla", file]))
      end

      on_exit(fn -> File.rm_rf!(root) end)

      minimal = Loader.load!(root)["siala_41"]

      assert minimal.skill_rules == %{
               save_bonus: [],
               stealth_multiclass_penalty: nil,
               class_level_bonuses: []
             }

      assert minimal.systems == []

      build =
        BuildCalculator.Rules.Build.new(
          levels: [:rogue, :fighter, :wizard, :cleric],
          skills: %{1 => %{spellcraft: 20}}
        )

      assert Skills.save_bonus(build, minimal, 4) == {0, []}
      assert Skills.modifiers(build, minimal, 4) == %{}
    end
  end
end
