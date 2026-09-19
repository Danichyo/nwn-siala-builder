defmodule BuildCalculator.Data.RepeatedGrantsTest do
  @moduledoc """
  Classes that grant a feat id they already granted at a lower level.

  **87 such places, across 13 classes**, and **none of them is a duplicate**. The
  wiki keeps one page per ability family, so distinct ranks resolve to one id;
  `progression[].feats_raw` still tells them apart:

      barbarian    1  [[barbarian rage]] (1x/day)   15  [[greater rage]] (4x/day)
      pale master  5  [[deathless vigor]] (+3HP)    15  [[deathless vigor]] (+5HP)
      shifter     13  [[infinite humanoid shape]]   16  [[infinite greater wildshape]] IV

  So the grant is kept — dropping it would hide a real gain, where showing the
  family name is merely imprecise.

  ⚠️ Здесь стояло «across six classes» без числа мест, и то же самое —
  «ten such places, across six classes» — стояло в комментарии `loader.ex`
  (исправлено 10.08.2026). Данные ушли на 87 в 13 классах ещё 08.08.2026, когда
  `ClassPage.feat_grants/1` научился читать семейство, названное прозой после
  первой ссылки. Отсюда **два разных пина, а не копия одного**: `Wiki.ClassGrantRanksTest`
  держит число по JSON-снапшоту, этот файл — по ruleset'у, который собрал загрузчик.
  Что это правда разные списки, видно прямо здесь: число одинаковое, а место
  повтора у Рыцаря Пурпурного Дракона сиальский слой сдвинул с 4-го классового
  уровня на 8-й.

  What is new is that the imprecision has a cure: the parser now carries the
  tail of the fragment into `granted_feat_ranks`, so most of these can be named
  exactly. The rule this file exists to pin is therefore **an "if and only if"**:
  a repeat is reported when, and only when, its rank is unnamed.

  ⚠️ Здесь стояло «not a count» — и это верно ровно про **число гэпов**: оно
  меняется, как только парсер назовёт ступень ещё у одного повтора, и пин на нём
  запрещал бы починку. Про **число мест** обратное: его печатает прозой
  `loader.ex`, проза не падает, и именно так «десять мест в шести классах»
  прожили в комментарии два дня после того, как стали неверны.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Data.Loader
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.Build

  setup_all do
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  defp reported(ruleset) do
    for {:not_modelled, {:unnamed_grant_rank, class, level, feat}} <- ruleset.gaps,
        do: {class, level, feat}
  end

  # Every place a class hands the same feat id over twice, with whatever rank
  # the data names for the later grant. Deliberately computed here rather than
  # taken from the loader: the point is to check the loader against the data,
  # not against itself.
  defp repeats(ruleset) do
    for {id, class} <- ruleset.classes,
        {level, feats} <- class.granted_feats,
        feat <- feats,
        Enum.any?(class.granted_feats, fn {earlier, ids} -> earlier < level and feat in ids end),
        do: {{id, level, feat}, class.granted_feat_ranks |> Map.get(level, %{}) |> Map.get(feat)}
  end

  defp place_set(ruleset),
    do: for({place, _rank} <- repeats(ruleset), into: MapSet.new(), do: place)

  describe "a repeated grant is kept, not dropped" do
    test "barbarian still gains something at 15", %{siala: rs} do
      assert :barbarian_rage in rs.classes[:barbarian].granted_feats[15]
    end

    test "the dwarven defender keeps all three steps of defensive awareness", %{siala: rs} do
      granted = rs.classes[:dwarven_defender].granted_feats

      for level <- [2, 5, 10] do
        assert :defensive_awareness in granted[level],
               "уровень #{level} потерял ступень Defensive Awareness"
      end
    end

    test "the shifter keeps both wildshape steps", %{siala: rs} do
      granted = rs.classes[:shifter].granted_feats

      assert :infinite_greater_wildshape in granted[13]
      assert :infinite_greater_wildshape in granted[16]
    end
  end

  # Вторая половина того же следствия «одна страница — одно семейство», и она про
  # ТРЕБОВАНИЯ, а не про показ. Под id `barbarian_rage` живут две разные игровые
  # способности: `Barbarian rage` (1x/day с 1-го уровня класса) и `Greater rage`
  # (4x–6x, с 15-го) — страница `Greater rage` на Fandom это редирект на
  # `Barbarian rage`, и наш маппинг разрешает его правильно
  # (`priv/wiki_cache/fandom/Barbarian rage.wikitext`, revid 71367, снято
  # 01.08.2026: `{{redirect|Greater rage|the monster ability|…}}`).
  #
  # ⚠️ Отсюда ловушка, ради которой стоит этот блок: три эпических фита требуют
  # СТУПЕНЬ, а не фит, и записать это требование как `feats: [barbarian_rage]`
  # значило бы выдать ступень 1x/day за 6x/day — то есть открыть эпический фит
  # варвару первого уровня.
  #
  # ⚠️ Здесь стояло «схема ступеней не выражает, поэтому требование осталось
  # в `unparsed`, и ядро честно отказывает „не прочитано“» — с 10.08.2026 это
  # не так. Ступень выражена тем, во что её переводит сама страница: УРОВНЕМ
  # КЛАССА (`priv/rules/vanilla/feat_requirements.json`, три записи `applied`).
  # Отказ остался, но стал структурным — `{:requires_class_level, :barbarian, N}`
  # вместо `{:missing_data, …}`, — а фиты перестали быть недостижимыми вовсе.
  # Ловушка при этом никуда не делась: она ровно в том, чтобы вместо уровня
  # класса написать `feats: [barbarian_rage]`, и её держит тест ниже.
  #
  # source: fandom:Mighty rage (revid 69992, снято 01.08.2026) —
  # «21st level, strength 21+, constitution 21+, [[greater rage]] (6x per day)»,
  # и в Notes та же страница сама переводит ступень: «This feat's prerequisites
  # require barbarian level 20.»
  # source: fandom:Thundering rage (revid 68111) и fandom:Terrifying rage
  # (revid 70525) — «[[greater rage]] (4x per day)», в Notes «obtained at
  # barbarian level 15» / «only 15 of them need to be barbarian levels».
  describe "the collapsed id is not a key to the family's requirements" do
    setup %{siala: siala} do
      # Воин 20 / варвар 1 на 21-м: `barbarian_rage` у него ЕСТЬ (первая ступень),
      # ступени 6x/day нет и быть не может — до неё нужен варвар 20.
      %{
        build:
          Build.new(
            race: :human,
            alignment: :chaotic_good,
            base_abilities: %{str: 21, dex: 12, con: 21, int: 10, wis: 10, cha: 8},
            levels: List.duplicate(:fighter, 20) ++ [:barbarian]
          ),
        ruleset: siala
      }
    end

    test "владение первой ступенью эпический фит не открывает", %{
      build: build,
      ruleset: ruleset
    } do
      # Положительный контроль: id действительно на руках, отказ не от того, что
      # выдачи нет вовсе.
      assert :barbarian_rage in Build.feats_permanent(build, ruleset, 21)

      for id <- [:mighty_rage, :thundering_rage, :terrifying_rage] do
        assert match?({:error, _reasons}, Rules.validate_feat(build, id, ruleset)),
               ":#{id} открылся варвару 1-го уровня по id первой ступени"
      end

      # Второй положительный контроль: на этом же билде эпический фит, требования
      # которого схема выражает, берётся — значит отказ выше про ступень, а не
      # про «здесь всё запрещено».
      assert Rules.validate_feat(build, :epic_prowess, ruleset) == :ok
    end

    # Пин на СЕГОДНЯШНЮЮ форму отказа, а не на правило — и форма сменилась
    # 10.08.2026, ровно как здесь и было предсказано: ступень записана уровнем
    # класса, поэтому причина стала структурной и НАЗЫВАЕТ, чего не хватает,
    # вместо «требования не прочитаны». Тест выше — тот, который переписывать
    # не пришлось.
    test "причина называет уровень класса, а не «требование не прочитано»", %{
      build: build,
      ruleset: ruleset
    } do
      for {id, level} <- [mighty_rage: 20, thundering_rage: 15, terrifying_rage: 15] do
        assert {:error, reasons} = Rules.validate_feat(build, id, ruleset)
        assert {:requires_class_level, :barbarian, level} in reasons

        refute {:missing_data, {:feat_prerequisites, id}} in reasons,
               ":#{id} снова отказывает «не прочитано» — требование потеряло структуру"
      end
    end
  end

  describe "reported if and only if the rank is unnamed" do
    # Guards the two tests below from passing vacuously on an empty list — and,
    # since 10.08.2026, pins the number `loader.ex` states in prose right above
    # `repeated_grants/1`, because prose does not fail.
    test "87 repeats across 13 classes on both rulesets", %{siala: siala, vanilla: vanilla} do
      for rs <- [siala, vanilla] do
        places = repeats(rs)
        classes = for {{class, _level, _feat}, _rank} <- places, uniq: true, do: class

        assert length(places) == 87
        assert length(classes) == 13
      end
    end

    # ⚠️ Число одинаковое, а МЕСТА — нет, и это то, из-за чего два пина (здесь и
    # по JSON-снапшоту в `Wiki.ClassGrantRanksTest`) — два разных утверждения, а
    # не копия одного: шард растянул раздачу Рыцаря Пурпурного Дракона вдвое, и
    # второй `inspire_courage` уехал с 4-го классового уровня на 8-й. Ровно одно
    # место сдвинулось, ни одного не появилось и не исчезло.
    test "одно место сдвинуто сиальским слоем, остальные 86 совпадают", %{
      siala: siala,
      vanilla: vanilla
    } do
      only_in = fn a, b ->
        MapSet.difference(place_set(a), place_set(b)) |> Enum.sort()
      end

      assert only_in.(vanilla, siala) == [{:purple_dragon_knight, 4, :inspire_courage}]
      assert only_in.(siala, vanilla) == [{:purple_dragon_knight, 8, :inspire_courage}]
    end

    # The other half of that number, and the reason the loader is silent here:
    # 87 of 87 carry a rank, so neither ruleset holds a single
    # `{:unnamed_grant_rank, …}`. Положительный контроль к пустому списку — блок
    # «the rule itself, on fixtures» ниже: там та же машинерия гэп выдаёт.
    test "no repeat is left unnamed today", %{siala: siala, vanilla: vanilla} do
      for rs <- [siala, vanilla] do
        assert reported(rs) == []

        for {place, rank} <- repeats(rs) do
          assert is_binary(rank), "#{inspect(place)}: повтор без ступени, а гэпа нет"
        end
      end
    end

    test "a repeat with a named rank is not reported, one without it is", %{siala: rs} do
      for {place, rank} <- repeats(rs) do
        if is_nil(rank) do
          assert place in reported(rs), "#{inspect(place)}: ступени нет, а гэпа нет"
        else
          refute place in reported(rs), "#{inspect(place)}: ступень «#{rank}», а гэп есть"
        end
      end
    end

    test "nothing is reported that is not a repeat", %{siala: rs} do
      places = for {place, _rank} <- repeats(rs), do: place

      for place <- reported(rs) do
        assert place in places, "#{inspect(place)} объявлен повтором, но раньше не выдавался"
      end
    end

    # Nothing here comes from the shard — the collapse is a property of how
    # Fandom is organised, so vanilla has to report the same places.
    #
    # ⚠️ Сегодня обе стороны ПУСТЫ (тест «no repeat is left unnamed today»), то
    # есть проверка держит форму правила, а не наблюдение. Сказано вслух, чтобы
    # зелёный цвет здесь не читался как «сверка прошла».
    test "vanilla reports the same set", %{siala: siala, vanilla: vanilla} do
      assert Enum.sort(reported(vanilla)) == Enum.sort(reported(siala))
    end

    # source: priv/rules/vanilla/classes.json — the ranks the parser reads off
    # `progression[].feats_raw`. Pinned by name because they are the payoff:
    # every one of the 87 places used to be a gap.
    test "the ranks the wiki does state are carried through", %{siala: rs} do
      assert rs.classes[:dwarven_defender].granted_feat_ranks[5][:defensive_awareness] == "II"
      assert rs.classes[:dwarven_defender].granted_feat_ranks[10][:defensive_awareness] == "III"
      assert rs.classes[:pale_master].granted_feat_ranks[15][:deathless_vigor] == "(+5HP)"
    end
  end

  # The contract is written against fixtures as well as the snapshot: the
  # snapshot happens to name every rank today, so on it alone the "unnamed is
  # reported" half of the rule would never fire.
  describe "the rule itself, on fixtures" do
    @describetag :tmp_dir

    test "a repeat is a gap exactly while its rank is missing", %{tmp_dir: dir} do
      ruleset =
        load(dir, [
          %{
            "id" => "fighter",
            "name" => "Fighter",
            "granted_feats" => %{"2" => ["ward"], "5" => ["ward"], "10" => ["ward"]},
            "granted_feat_ranks" => %{"5" => %{"ward" => "II"}}
          }
        ])

      reported = reported(ruleset)

      refute {:fighter, 5, :ward} in reported
      assert {:fighter, 10, :ward} in reported
    end

    test "a class with no ranks at all reports every repeat", %{tmp_dir: dir} do
      ruleset =
        load(dir, [
          %{
            "id" => "fighter",
            "name" => "Fighter",
            "granted_feats" => %{"1" => ["ward"], "7" => ["ward"]}
          }
        ])

      assert reported(ruleset) == [{:fighter, 7, :ward}]
    end

    # A shift moves the grant; if the rank stayed behind it would end up
    # labelling the level the feat left, and the level it arrived at would look
    # unnamed. Both halves are checked, because either failure is silent.
    test "a shard level shift carries the rank with the grant", %{tmp_dir: dir} do
      ruleset =
        load(
          dir,
          [
            %{
              "id" => "fighter",
              "name" => "Fighter",
              "granted_feats" => %{"1" => ["ward"], "7" => ["ward"]},
              "granted_feat_ranks" => %{"7" => %{"ward" => "II"}}
            }
          ],
          %{
            "classes" => [
              %{
                "vanilla_id" => "fighter",
                "changes" => [
                  %{
                    "what" => "feat_level_shift",
                    "value" => [%{"feat" => "ward", "from" => 7, "to" => 9}],
                    "status" => "verified"
                  }
                ]
              }
            ]
          }
        )

      fighter = ruleset.classes[:fighter]

      assert fighter.granted_feats[9] == [:ward]
      assert fighter.granted_feat_ranks == %{9 => %{ward: "II"}}
      assert reported(ruleset) == []
    end
  end

  # A rules directory with only what the loader insists on: the epic file (taken
  # from the real snapshot, so the cross-checks it feeds stay honest) and the
  # classes under test.
  defp load(dir, classes, shard_classes \\ nil) do
    File.mkdir_p!(Path.join(dir, "vanilla"))

    File.cp!(
      Path.join(File.cwd!(), "priv/rules/vanilla/epic.json"),
      Path.join([dir, "vanilla", "epic.json"])
    )

    File.write!(Path.join([dir, "vanilla", "classes.json"]), Jason.encode!(classes))

    if shard_classes do
      File.mkdir_p!(Path.join(dir, "siala_41"))
      File.write!(Path.join([dir, "siala_41", "classes.json"]), Jason.encode!(shard_classes))
    end

    Loader.load!(dir)["siala_41"]
  end
end
