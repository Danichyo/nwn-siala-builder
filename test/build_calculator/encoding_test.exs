defmodule BuildCalculator.EncodingTest do
  @moduledoc """
  The URL codec, which in v1 is the save file.

  The frozen fixture below is the important test in this file: it is a real v1
  code, checked in, and it must keep decoding no matter what the format does
  next. Somebody has that link in a Discord message.
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculator.Rules
  alias BuildCalculator.Rules.{Build, Gear}
  alias BuildCalculator.{Encoding, Ids}

  # A Dwarf Fighter 4 / Dwarven defender 2 with feats, an ability increase and
  # skills, encoded by v1 on 2026-08-01. Do not regenerate it — the point is
  # that it was written by an older version of this module.
  @frozen_v1 "1.bYxLDsIgFAD5aWttYhNPYuLKy5AnPCiRQMOjxeNbE5cuZjczvKcAEfT9drANijtHaG6N2udsj9LM0EuT00VafI8ypDpIqmWSLdAopm-xYdIWHSaLpXPBzxWL4IrtKCaPJiJsOC65YdFQK5jXqebVzwmJmORXE4FIP3Na6fHLGeedx4QFIhPir8HEYAOZsMSQUNGS6_5iinMhGP8A"

  # The same build once gear joined the payload, encoded by v2 on 2026-08-01.
  @frozen_v2 "2.bYxBDoIwEEWnLQIiiSSexMSVl2nGdoDGpiWdQj2-GF36k7d778uWHXrUt-vBFkzjyWMZV6-nGG2tzIytMjGclaVXr1zIneKcBlUc93L4FBsFbWmkYCk1o5vmTEmKCnYqULXxhBv1SyyUNOaM5nnMcZ3mQMygxMV4ZNaPGFa-_3IQopkoUEIPUv41QHbWsXGLd4EqXmLev6ASQkoQ8N0b"

  defp sample do
    Build.new(
      ruleset_version: "siala_41",
      race: :dwarf,
      alignment: :lawful_good,
      base_abilities: %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8},
      levels: [:fighter, :fighter, :fighter, :fighter, :dwarven_defender, :dwarven_defender],
      ability_increases: %{4 => :str},
      feats: %{
        1 => %{:general => :toughness, {:class_bonus, :fighter} => :power_attack},
        2 => %{{:class_bonus, :fighter} => :cleave}
      },
      skills: %{1 => %{discipline: 4, spot: 2}, 2 => %{discipline: 1}}
    )
  end

  defp geared do
    %Build{} = build = sample()

    %Build{
      build
      | gear: Gear.new(abilities: %{str: 6, con: 12}, ac: %{armor: 8, deflection: 5}, saves: 12),
        spells: %{7 => %{{:circle, 3, 0} => :fireball, {:circle, 1, 0} => :magic_missile}}
    }
  end

  describe "round trip" do
    test "a full build survives encode and decode unchanged" do
      build = sample()

      assert {:ok, %{build: decoded, ruleset: ruleset, dropped: []}} =
               Encoding.decode(Encoding.encode(build))

      assert decoded == build
      assert ruleset.version == "siala_41"
    end

    test "an empty build survives too" do
      build = Build.new(ruleset_version: Data.default_version())

      assert {:ok, %{build: ^build}} = Encoding.decode(Encoding.encode(build))
    end

    test "the order classes were taken in is preserved, not sorted" do
      # Past character level 20 the order decides base attack outright
      # (CLAUDE.md §3), so this is not a cosmetic property.
      build =
        Build.new(
          ruleset_version: "siala_41",
          levels: [:wizard, :fighter, :wizard, :fighter, :fighter]
        )

      assert {:ok, %{build: decoded}} = Encoding.decode(Encoding.encode(build))
      assert decoded.levels == [:wizard, :fighter, :wizard, :fighter, :fighter]
    end

    test "the code is short enough to paste into a chat message" do
      build = Build.new(ruleset_version: "siala_41", levels: List.duplicate(:fighter, 41))

      assert byte_size(Encoding.encode(build)) < 400
    end

    test "the code is url safe and names its schema version" do
      code = Encoding.encode(sample())

      assert String.starts_with?(code, "#{Encoding.current_version()}.")
      assert code == URI.encode(code, &URI.char_unreserved?/1)
    end

    # Долг §7 AGENT_QUEUE.md, «шестая пятёрка». Кодек пишет слоты уровня в своём
    # порядке (`Ids.slot_key/1` — `"class_bonus:…"` раньше `"general"`), а на
    # экран они выходят в другом (`Build.slot_order/1` — общий и расовый первыми).
    # Это НЕ баг, и вот проверка, которая делает разницу безвредной по существу,
    # а не по случайности: декодированный билд — карта, и порядок в байтах на него
    # не влияет вовсе.
    test "the codec's own slot order is not the one people read, and nothing depends on it" do
      slots = %{
        :general => :toughness,
        :racial => :power_attack,
        {:class_bonus, :fighter} => :weapon_focus
      }

      build =
        Build.new(
          ruleset_version: "siala_41",
          levels: [:fighter],
          feats: %{1 => slots}
        )

      assert {:ok, %{build: decoded, dropped: []}} = Encoding.decode(Encoding.encode(build))
      assert decoded.feats == build.feats

      # Два порядка действительно разные — иначе тест зеленел бы ни о чём.
      keys = Map.keys(slots)

      assert Enum.sort_by(keys, &Ids.slot_key/1) != Enum.sort_by(keys, &Build.slot_order/1)

      # И код детерминирован: один и тот же билд кодируется одинаково, откуда бы
      # ни пришла карта слотов.
      assert Encoding.encode(decoded) == Encoding.encode(build)
    end
  end

  describe "gear and spells" do
    test "gear survives the round trip, uncapped and untouched" do
      # The codec stores what the player typed; the ceilings are the rules
      # core's business, so a hand-edited link never silently loses its numbers.
      build = geared()

      assert {:ok, %{build: decoded, dropped: []}} = Encoding.decode(Encoding.encode(build))
      assert decoded == build
      assert decoded.gear.abilities == %{str: 6, con: 12}
      assert decoded.gear.ac == %{armor: 8, deflection: 5}
      assert decoded.gear.saves == 12
    end

    test "spell slots keep the circle and index they were chosen in" do
      assert {:ok, %{build: decoded}} = Encoding.decode(Encoding.encode(geared()))

      assert decoded.spells[7][{:circle, 3, 0}] == :fireball
      assert decoded.spells[7][{:circle, 1, 0}] == :magic_missile
    end

    test "a spell the data no longer knows is dropped and reported" do
      # gear: no abilities, no AC, no save bonus
      # one spell nobody has ever heard of, used once
      payload =
        <<2::8>> <>
          str("siala_41") <>
          str("") <>
          str("") <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::16>> <>
          <<0::16>> <>
          <<0::8>> <>
          <<0::16>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<1::16>> <>
          str("nonexistent_spell") <>
          <<1::16, 3::8, 2::8, 0::8, 0::16>>

      code = "2." <> Base.url_encode64(:zlib.zip(payload), padding: false)

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(code)
      assert build.spells == %{}
      assert {:unknown_spell, "nonexistent_spell"} in dropped
      assert_raise ArgumentError, fn -> String.to_existing_atom("nonexistent_spell") end
    end
  end

  describe "old links" do
    test "a v1 code written before today still opens" do
      assert {:ok, %{build: build, dropped: []}} = Encoding.decode(@frozen_v1)

      assert build.race == :dwarf
      assert build.alignment == :lawful_good

      assert build.levels == [
               :fighter,
               :fighter,
               :fighter,
               :fighter,
               :dwarven_defender,
               :dwarven_defender
             ]

      assert build.base_abilities == %{str: 16, dex: 12, con: 15, int: 10, wis: 12, cha: 8}
      assert build.ability_increases == %{4 => :str}
      assert build.feats[1][:general] == :toughness
      assert build.feats[1][{:class_bonus, :fighter}] == :power_attack
      assert build.skills == %{1 => %{discipline: 4, spot: 2}, 2 => %{discipline: 1}}
    end

    test "a v1 code opens as the build it described: no gear, no spells" do
      assert {:ok, %{build: build}} = Encoding.decode(@frozen_v1)

      assert build.gear == %Gear{}
      assert build.spells == %{}
    end

    test "the frozen v2 fixture is exactly what today's encoder writes" do
      # If this fails the format changed, which is allowed — but then the
      # version must be bumped and every older fixture kept decoding.
      assert Encoding.encode(sample()) == @frozen_v2
    end

    test "v1 is no longer written, only read" do
      refute String.starts_with?(Encoding.encode(sample()), "1.")
      assert Encoding.current_version() == 2
    end

    # 🔴 Задача 3.41 сделала доспех и щит ПРЕДМЕТАМИ, из которых берётся база
    # AC и предел ловкости. В уже расшаренных ссылках предмета не записано, и
    # решение на этот счёт названо словами (`Encoding`'s moduledoc): предмета
    # нет — значит нет ни базы, ни предела, а вписанное под типом число
    # остаётся тем, чем было, — бонусом.
    #
    # ⚠️ Фикстура снята прогоном кода **до** правки (`git stash`), а не
    # сгенерирована сегодняшним кодером: смысл в том, что её написала прошлая
    # версия модуля. Числа рядом — то, что тот же прогон печатал.
    @frozen_v2_geared "2.LcpRCsIwDADQ1ayzFNmHNxG8zwhtZgNdCmnKPL4ovu93CZ2x4vZ8-DIOlJvpoE1omGJdIBUMkJqskOl9BxaL0E1XOLlHd935VYzUTXH6c984g0c9moaYaa-UjJv4pRemmudf-wA"

    test "ссылка, записанная ДО предметов, открывается и даёт то же AC" do
      assert {:ok, %{build: build, ruleset: ruleset, dropped: []}} =
               Encoding.decode(@frozen_v2_geared)

      # Надетого в ней нет вовсе — и это ответ, а не пробел.
      assert build.gear.worn == %{}
      assert build.gear.ac == %{armor: 8, shield: 4, deflection: 5}

      stats = Rules.compute(build, ruleset)

      # Ровно те числа, что печатал прогон до правки: 10 базы + 6 ловкости
      # (DEX 18 и +4 с вещей) + 17 вписанного по трём типам.
      assert stats.ac_naked == 14
      assert stats.ac_geared == 33
      assert stats.ref == 9
      assert stats.attack_bonus == 12

      # ...и вписанное доехало целиком, а не стало «бонусом поверх базы»,
      # которой в ссылке нет.
      assert stats.ac_by_type == [armor: 8, shield: 4, deflection: 5, natural: 0, dodge: 0]
      assert stats.ac_dexterity == %{modifier: 6, counted: 6, cap: nil, capped?: false}
    end

    # ⚠️ Положительный контроль к строке выше: тот же билд, но с названным
    # предметом, число МЕНЯЕТ. Иначе «то же AC» зеленело бы и на модели, где
    # предметы не считаются вовсе.
    test "тот же билд с названным доспехом считается иначе" do
      assert {:ok, %{build: %Build{} = build, ruleset: ruleset}} =
               Encoding.decode(@frozen_v2_geared)

      dressed = %Build{build | gear: Gear.put_worn(build.gear, :armor, :full_plate)}
      stats = Rules.compute(dressed, ruleset)

      # 8 базы лат прибавились, а ловкость срезана с +6 до +1.
      assert stats.ac_geared == 33 + 8 - 5
      assert stats.ac_dexterity == %{modifier: 6, counted: 1, cap: 1, capped?: true}

      # А рефлекс и атака — как были: предел ловкости их не касается.
      assert stats.ref == 9
      assert stats.attack_bonus == 12
    end

    # И обратная сторона: билд БЕЗ надетого кодируется побайтово как раньше —
    # то есть новая запись не сменила код каждому уже расшаренному билду.
    test "билд без надетого кодируется побайтово так же, как раньше" do
      assert {:ok, %{build: %Build{} = build}} = Encoding.decode(@frozen_v2_geared)
      assert Encoding.encode(build) == @frozen_v2_geared

      # Положительный контроль: с надетым код ДРУГОЙ.
      dressed = %Build{build | gear: Gear.put_worn(build.gear, :shield, :tower)}
      refute Encoding.encode(dressed) == @frozen_v2_geared
    end

    test "надетое переживает круг, обе половины пары" do
      %Build{} = build = sample()
      dressed = %Build{build | gear: Gear.new(worn: %{armor: :half_plate, shield: :small})}

      assert {:ok, %{build: back, dropped: []}} = Encoding.decode(Encoding.encode(dressed))
      assert back.gear.worn == %{armor: :half_plate, shield: :small}
    end

    # ⚠️ Неизвестное теряется ПОИМЁННО, а не молча: ссылка на доспех, которого
    # в справочнике больше нет, иначе открылась бы как «доспеха и не было» —
    # с завышенным AC и без предела ловкости.
    test "надетое, которого справочник не знает, названо в выпавшем" do
      for pair <- ["worn|armor|mithral_shirt", "worn|helmet|full_plate", "worn|armor"] do
        code = code_with_slot(pair)

        assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(code)
        assert build.gear.worn == %{}
        assert {:unknown_worn, "worn|" <> _} = List.first(dropped)
      end

      # Положительный контроль: пара, которую справочник знает, не выпадает.
      assert {:ok, %{build: ok, dropped: []}} =
               Encoding.decode(code_with_slot("worn|shield|large"))

      assert ok.gear.worn == %{shield: :large}
    end

    # Голый каркас v2 с одной строкой таблицы фитов: уровень 0 и заданный ключ
    # слота. Индекс фита нулевой — такая строка читается по ключу, до таблицы
    # имён дело не доходит.
    defp code_with_slot(slot_key) do
      payload =
        <<2::8>> <>
          str("siala_41") <>
          str("") <>
          str("") <>
          <<0::8, 0::8, 0::8, 0::8>> <>
          <<0::16>> <>
          <<1::16, 0::8>> <>
          <<byte_size(slot_key)::8>> <>
          slot_key <>
          <<0::16>> <>
          <<0::8, 0::16>> <>
          <<0::8, 0::8, 0::8, 0::16, 0::16>>

      "2." <> Base.url_encode64(:zlib.zip(payload), padding: false)
    end
  end

  describe "фит, взятый с выбором" do
    defp with_choices do
      %Build{} = build = sample()

      %Build{
        build
        | feats: %{
            1 => %{
              :general => {:spell_focus, :evocation},
              {:class_bonus, :fighter} => :power_attack
            },
            2 => %{{:class_bonus, :fighter} => {:favored_enemy, :goblinoid}}
          }
      }
    end

    test "пара доезжает до слота целиком" do
      assert {:ok, %{build: back, dropped: []}} = Encoding.decode(Encoding.encode(with_choices()))

      assert back.feats[1][:general] == {:spell_focus, :evocation}
      assert back.feats[2][{:class_bonus, :fighter}] == {:favored_enemy, :goblinoid}

      # Соседний слот того же уровня остался голым атомом, а не парой с nil.
      assert back.feats[1][{:class_bonus, :fighter}] == :power_attack
    end

    test "билд БЕЗ выборов кодируется побайтово так же, как раньше" do
      # ⚠️ Ради этого выбор и уехал внутрь строки таблицы фитов, а не в новую
      # секцию с бампом версии: новая версия сменила бы код каждому билду,
      # включая те, где выбора нет. Отдельный assert рядом с замороженной
      # фикстурой — потому что фикстура проверяет ОДИН билд, а правило шире.
      assert String.starts_with?(Encoding.encode(sample()), "2.")
      assert Encoding.encode(sample()) == @frozen_v2

      # Положительный контроль: код с выбором ДРУГОЙ — иначе первые два
      # assert'а зеленели бы и на кодеке, который выбор молча теряет.
      refute Encoding.encode(with_choices()) == Encoding.encode(sample())
    end

    test "версия не выросла — старые ссылки читает тот же парсер" do
      assert Encoding.current_version() == 2
      assert {:ok, %{build: %Build{}}} = Encoding.decode(@frozen_v1)
    end

    test "значение, которого нет в справочнике, роняет пик целиком и говорит об этом" do
      # ⚠️ Не «оставить фит без школы»: снаружи такой пик неотличим от честно
      # выбранного, а школа при этом потеряна молча.
      {:ok, %{build: ok}} = Encoding.decode(Encoding.encode(with_choices()))
      assert ok.feats[1][:general] == {:spell_focus, :evocation}

      %Build{} = base = with_choices()

      broken =
        %Build{base | feats: %{1 => %{general: {:spell_focus, :evocation}}}}
        |> Encoding.encode()
        |> tamper("evocation", "elocution")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert dropped == [{:unknown_choice, "spell_focus|elocution"}]
      assert build.feats == %{}
    end

    # Подменяет строку внутри сжатого payload'а, не трогая раскладку байт:
    # длина совпадает, поэтому length-prefix остаётся верным.
    defp tamper("2." <> body, from, to) do
      payload =
        body
        |> Base.url_decode64!(padding: false)
        |> :zlib.unzip()
        |> String.replace(from, to)

      "2." <> Base.url_encode64(:zlib.zip(payload), padding: false)
    end
  end

  describe "второй бонусный слот класса на одном уровне (рейнджер 35)" do
    # ⚠️ Форма `{:class_bonus, class, index}` появилась 14.08.2026 вместе
    # с починкой «рейнджер теряет фит на 35-м классовом уровне»
    # (`Rules.FeatSlots`). Кодек — то место, где новая форма стоит дороже
    # всего: ключ слота едет в ссылке строкой, а `build.feats[level]` —
    # карта по этому ключу, так что форма, которую кодек не умеет писать
    # или читать, теряет пик молча.
    defp with_two_bonus_slots do
      Build.new(
        ruleset_version: "siala_41",
        race: :human,
        levels: List.duplicate(:ranger, 41),
        feats: %{
          35 => %{
            {:class_bonus, :ranger} => {:favored_enemy, :dwarf},
            {:class_bonus, :ranger, 2} => {:favored_enemy, :elf}
          }
        }
      )
    end

    test "круглый рейс: оба пика на месте, и это два РАЗНЫХ пика" do
      assert {:ok, %{build: back, dropped: []}} =
               Encoding.decode(Encoding.encode(with_two_bonus_slots()))

      assert back.feats[35][{:class_bonus, :ranger}] == {:favored_enemy, :dwarf}
      assert back.feats[35][{:class_bonus, :ranger, 2}] == {:favored_enemy, :elf}
      assert map_size(back.feats[35]) == 2
    end

    test "ключ слота — та же строка в обе стороны" do
      assert Ids.slot_key({:class_bonus, :ranger, 2}) == "class_bonus:ranger:2"

      assert Ids.fetch_slot(Data.ruleset!("siala_41"), "class_bonus:ranger:2") ==
               {:ok, {:class_bonus, :ranger, 2}}
    end

    # 🔴 Совместимость уже расшаренных ссылок, ради которой ПЕРВЫЙ слот
    # индекса не получил: `"class_bonus:ranger"` — это строка, которая уже
    # лежит в чужих сообщениях в Discord, и переименуй мы её, пик из такой
    # ссылки перестал бы совпадать с любым слотом уровня. Проверяется на
    # замороженной фикстуре, а не на свежесозданном билде: она написана
    # СТАРОЙ сборкой, до появления второй формы.
    test "старый код с бонусным слотом читается ровно как раньше" do
      assert {:ok, %{build: v1, dropped: []}} = Encoding.decode(@frozen_v1)
      assert v1.feats[1][{:class_bonus, :fighter}] == :power_attack

      assert {:ok, %{build: v2, dropped: []}} = Encoding.decode(@frozen_v2)
      assert v2.feats[1][{:class_bonus, :fighter}] == :power_attack

      # …и сегодняшний кодировщик пишет ту же строку, что писал до правки.
      assert Encoding.encode(sample()) == @frozen_v2
    end

    # `"class_bonus:ranger:1"` — второе написание первого слота, и принять его
    # значило бы завести две строки на один вход карты `build.feats[level]`.
    test "первый слот пишется ровно одним способом" do
      ruleset = Data.ruleset!("siala_41")

      assert Ids.fetch_slot(ruleset, "class_bonus:ranger:1") == :error
      assert Ids.fetch_slot(ruleset, "class_bonus:ranger:0") == :error
      assert Ids.fetch_slot(ruleset, "class_bonus:ranger:x") == :error
      assert Ids.fetch_slot(ruleset, "class_bonus:nosuchclass:2") == :error
    end
  end

  describe "выбор класса (домены клирика, задача 3.14)" do
    # Реальный ruleset, а не фикстура: домен `:domain` резолвится через
    # `ruleset.choice_domains`, ту же таблицу, что и у выбора фитов, а её
    # строит загрузчик из `priv/rules/vanilla/domains.json` — кодек её не
    # выдумывает, поэтому и тест не изобретает свой словарь.
    defp with_class_choice do
      Build.new(
        ruleset_version: "siala_41",
        race: :dwarf,
        levels: [:cleric, :cleric],
        # Нарочно не по алфавиту — round trip обязан вернуть отсортированную
        # пару независимо от порядка, в котором игрок кликал (см. ниже).
        class_choices: %{cleric: [:war, :air]}
      )
    end

    test "домены доезжают до билда целиком, отсортированными" do
      assert {:ok, %{build: back, dropped: []}} =
               Encoding.decode(Encoding.encode(with_class_choice()))

      assert back.class_choices == %{cleric: [:air, :war]}
      assert back.levels == [:cleric, :cleric]
    end

    test "билд БЕЗ выбора класса кодируется побайтово так же, как раньше" do
      # Тот же довод, что у выбора фитов: строка класса без выбора не должна
      # меняться, иначе версию пришлось бы поднимать ради каждого билда, а
      # не только ради тех, где выбор есть.
      assert Encoding.encode(sample()) == @frozen_v2

      # Положительный контроль: билд С выбором класса кодируется иначе.
      %Build{} = with_choice = with_class_choice()
      without_choice = %Build{with_choice | class_choices: %{}}
      refute Encoding.encode(with_choice) == Encoding.encode(without_choice)
    end

    test "версия не выросла — старые ссылки читает тот же парсер" do
      assert Encoding.current_version() == 2
      assert {:ok, %{build: %Build{}}} = Encoding.decode(@frozen_v1)
      assert {:ok, %{build: %Build{}}} = Encoding.decode(@frozen_v2)
    end

    test "старая ссылка без единого класса с выбором раскодируется с пустыми class_choices" do
      assert {:ok, %{build: build}} = Encoding.decode(@frozen_v2)
      assert build.class_choices == %{}
    end

    # ⚠️ Правило другое, чем у фита с выбором: там нечитаемое значение роняет
    # ПИК целиком (см. тест выше в этом файле), здесь класс и его уровни
    # остаются — уронить их из-за одного протухшего домена значило бы стереть
    # игроку сколько угодно уровней ради потери двух слов (`Encoding`'s
    # moduledoc, "Выбор класса").
    test "неизвестное значение выбора пропадает поодиночке, класс и уровни остаются" do
      %Build{} = base = with_class_choice()

      broken =
        %Build{base | class_choices: %{cleric: [:air]}}
        |> Encoding.encode()
        |> tamper("cleric|air", "cleric|xzz")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert dropped == [{:unknown_choice, "cleric|xzz"}]
      assert build.levels == [:cleric, :cleric]
      assert build.class_choices == %{}
    end

    # Положительный контроль на утверждение выше: класс без выбора при
    # порче ТОЖЕ теряет только строку выбора, а не самого себя — иначе
    # предыдущий тест зеленел бы просто потому, что порча ничего не находит.
    test "класс без домена в строке остаётся собой при порче ДРУГОГО билда" do
      code = Encoding.encode(sample())
      assert {:ok, %{build: build, dropped: []}} = Encoding.decode(code)
      assert build.levels != []
    end

    # ⚠️ Неизвестный КЛАСС продолжает ронять уровни целиком — это правило не
    # менялось, и суффикс выбора на нём не должен ничего чинить или ломать
    # иначе, чем раньше. Замена той же длины, что и у `tamper/3` выше в файле
    # (`evocation` → `elocution`): байтовая рамка держится на длине строки.
    test "неизвестный класс с дописанным доменом всё ещё роняет уровни целиком" do
      broken =
        Encoding.encode(with_class_choice())
        |> tamper("cleric|", "zclass|")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert build.levels == []
      assert {:unknown_class, "zclass"} in dropped
    end
  end

  describe "выбор класса — школа волшебника (задача 3.10)" do
    # ⚠️ Не переоткрытие того же теста другими словами: `class_choices`
    # хранится ОДНОЙ таблицей на любой класс (`common_payload/1`'s `classes`
    # секция), так что "домены доезжают" ничего не говорит о том, доезжает
    # ли НЕОБЯЗАТЕЛЬНЫЙ выбор с count:1. Волшебник — независимая проверка,
    # что механизм 3.14 действительно общий, а не подогнан под клирика.
    test "школа доезжает до билда — и одиночным значением, а не парой" do
      build =
        Build.new(
          ruleset_version: "siala_41",
          levels: [:wizard, :wizard],
          class_choices: %{wizard: [:evocation]}
        )

      assert {:ok, %{build: back, dropped: []}} = Encoding.decode(Encoding.encode(build))

      assert back.class_choices == %{wizard: [:evocation]}
      assert back.levels == [:wizard, :wizard]
    end

    # Положительный контроль на тест выше: билд СО школой кодируется иначе,
    # чем такой же билд без неё — иначе «доезжает» можно было бы получить
    # и от кодека, который выбор просто теряет.
    test "билд СО школой кодируется иначе, чем такой же билд без неё" do
      %Build{} = universal = Build.new(ruleset_version: "siala_41", levels: [:wizard])
      specialized = %Build{universal | class_choices: %{wizard: [:evocation]}}

      refute Encoding.encode(universal) == Encoding.encode(specialized)
    end

    # Старая ссылка (выпущена до задачи 3.10, а то и до 3.14) не несёт ни
    # одного домена — она обязана открыться со всеми уровнями на месте.
    test "старая ссылка без школы волшебника открывается без ошибок" do
      old_build =
        Build.new(
          ruleset_version: "siala_41",
          levels: List.duplicate(:wizard, 3),
          feats: %{5 => %{general: :toughness}}
        )

      code = Encoding.encode(old_build)

      assert {:ok, %{build: build, dropped: []}} = Encoding.decode(code)
      assert build.levels == List.duplicate(:wizard, 3)
      assert build.class_choices == %{}
    end
  end

  describe "фит с вещи (задача 3.3)" do
    defp with_gear_feats do
      %Build{} = build = sample()

      %Build{
        build
        | gear: Gear.new(abilities: %{con: 12}, saves: 5, feats: [:alertness, :weapon_focus])
      }
    end

    test "объявленные фиты доезжают до gear, а не в слоты" do
      assert {:ok, %{build: back, dropped: []}} =
               Encoding.decode(Encoding.encode(with_gear_feats()))

      assert back.gear.feats == [:alertness, :weapon_focus]

      # ⚠️ И ни один из них не оказался в лестнице: строка едет под псевдо-слотом
      # `"gear"` с уровнем 0, но собирается обратно в `gear`, а не в `feats`.
      assert back.feats == sample().feats
      assert back == with_gear_feats()
    end

    test "билд БЕЗ объявлений кодируется побайтово так же, как раньше" do
      # ⚠️ Тот же довод, что у выбора фита и у выбора класса, и здесь он был
      # единственной причиной не писать новую секцию в хвост v2: счётчик `0`
      # в хвосте занял бы байт у КАЖДОГО билда, включая те, где объявлений нет.
      assert Encoding.encode(sample()) == @frozen_v2

      # Положительный контроль: билд С объявлением кодируется иначе — иначе
      # assert выше зеленел бы и на кодеке, который список молча теряет.
      refute Encoding.encode(with_gear_feats()) == Encoding.encode(sample())
    end

    test "версия не выросла, старые ссылки читает тот же парсер" do
      assert Encoding.current_version() == 2
      assert {:ok, %{build: %Build{} = v1}} = Encoding.decode(@frozen_v1)
      assert {:ok, %{build: %Build{} = v2}} = Encoding.decode(@frozen_v2)

      # Ссылка, выпущенная до этой задачи, открывается с пустым списком —
      # ровно тем билдом, который она описывала.
      assert v1.gear.feats == []
      assert v2.gear.feats == []
    end

    # ⚠️ Плата, названная в moduledoc: код с объявлением, открытый СТАРОЙ
    # сборкой, потеряет строку и скажет об этом. Здесь это воспроизведено с той
    # стороны, которую можно проверить, — незнакомый ключ слота: старая сборка
    # ведёт себя так же, потому что `"gear"` для неё такой же незнакомый ключ.
    test "незнакомый ключ слота роняет строку и называет её, билд остаётся" do
      broken =
        with_gear_feats()
        |> Encoding.encode()
        |> tamper("gear", "gaer")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert {:unknown_slot, "gaer"} in dropped
      assert build.gear.feats == []

      # Остальное на месте: ни уровней, ни слотов, ни чисел с вещей не потеряно.
      assert build.levels == sample().levels
      assert build.feats == sample().feats
      assert build.gear.saves == 5
    end

    # ⚠️ Задача 3.97 развернула этот тест, и старое имя оставлено в комментарии
    # нарочно: он назывался «значение, дописанное к объявлению руками, теряется
    # НЕ молча» и проверял `dropped == [{:unknown_choice, …}]`. Кодек умел
    # прочитать пару и осознанно срезал значение, потому что объявление его
    # не несло. Теперь несёт (решение Dan, 25.08.2026), срезание снято — и
    # ссылка, которая до этой задачи была «правленой руками», стала обычной.
    #
    # Payload собран руками, а не порчей готового кода: подмена внутри сжатой
    # строки обязана быть той же длины (на ней держится length-prefix), а
    # `"spell_focus|evocation"` длиннее любого id в фикстуре.
    test "значение доезжает до объявления парой, а не срезается" do
      payload =
        <<2::8>> <>
          str("siala_41") <>
          str("") <>
          str("") <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<1::16>> <>
          str("spell_focus|evocation") <>
          <<1::16>> <>
          (<<0::8>> <> str("gear") <> <<0::16>>) <>
          <<0::8>> <>
          <<0::16>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::8>> <>
          <<0::16>> <>
          <<0::16>>

      code = "2." <> Base.url_encode64(:zlib.zip(payload), padding: false)

      assert {:ok, %{build: build, dropped: []}} = Encoding.decode(code)
      assert build.gear.feats == [{:spell_focus, :evocation}]
    end

    # Обратная сторона той же правки, и она важнее: голый id остался законным
    # состоянием, потому что ровно так записаны ВСЕ уже расшаренные ссылки
    # (решение Dan, 25.08.2026). Пара и голый id — два разных билда, и туда-
    # обратно каждый приезжает собой.
    test "голое объявление и объявление со значением ездят каждое собой" do
      %Build{} = base = sample()
      bare = %Build{base | gear: Gear.new(feats: [:spell_focus])}
      paired = %Build{base | gear: Gear.new(feats: [{:spell_focus, :evocation}])}

      assert {:ok, %{build: back_bare, dropped: []}} = Encoding.decode(Encoding.encode(bare))
      assert {:ok, %{build: back_paired, dropped: []}} = Encoding.decode(Encoding.encode(paired))

      assert back_bare.gear.feats == [:spell_focus]
      assert back_paired.gear.feats == [{:spell_focus, :evocation}]

      # Положительный контроль: коды РАЗНЫЕ. Без него тест зеленел бы и на
      # кодеке, который значение снова срезает, — оба билда просто съехались бы
      # в один.
      refute Encoding.encode(bare) == Encoding.encode(paired)
    end
  end

  describe "прибавка к навыку с вещей (задача 3.20)" do
    defp with_gear_skills do
      %Build{} = build = sample()

      %Build{build | gear: Gear.new(abilities: %{con: 12}, skills: %{discipline: 50, hide: 20})}
    end

    test "прибавки доезжают до gear, а не в ранги" do
      assert {:ok, %{build: back, dropped: []}} =
               Encoding.decode(Encoding.encode(with_gear_skills()))

      assert back.gear.skills == %{discipline: 50, hide: 20}

      # ⚠️ И ни одна из них не оказалась в рангах: строка едет уровнем 0 в той же
      # таблице навыков, но собирается обратно в `gear`. Спутать их дорого — ранги
      # на уровне 0 не увидел бы `Build.skill_ranks/3`, зато бюджет очков посчитал
      # бы их потраченными.
      assert back.skills == sample().skills
      assert back == with_gear_skills()
    end

    test "билд БЕЗ прибавок кодируется побайтово так же, как раньше" do
      # ⚠️ Тот же довод, что у выбора фита, выбора класса и фита с вещи: новая
      # секция в хвосте v2 заняла бы байт у КАЖДОГО билда, включая те, где
      # прибавок к навыкам нет.
      assert Encoding.encode(sample()) == @frozen_v2

      # Положительный контроль: билд С прибавкой кодируется иначе — иначе assert
      # выше зеленел бы и на кодеке, который прибавку молча теряет.
      refute Encoding.encode(with_gear_skills()) == Encoding.encode(sample())
    end

    test "версия не выросла, старые ссылки читает тот же парсер" do
      assert Encoding.current_version() == 2
      assert {:ok, %{build: %Build{} = v1}} = Encoding.decode(@frozen_v1)
      assert {:ok, %{build: %Build{} = v2}} = Encoding.decode(@frozen_v2)

      # Ссылка, выпущенная до этой задачи, открывается с пустой картой — ровно
      # тем билдом, который она описывала.
      assert v1.gear.skills == %{}
      assert v2.gear.skills == %{}

      # и её ранги на месте: строк с уровнем 0 в ней нет вовсе
      assert v1.skills == %{1 => %{discipline: 4, spot: 2}, 2 => %{discipline: 1}}
    end

    # Навык, которого справочник больше не знает, теряется поодиночке и назван —
    # тем же путём, что и ранги того же навыка (`resolve/3`).
    test "неизвестный навык теряется НЕ молча" do
      broken =
        with_gear_skills()
        |> Encoding.encode()
        |> tamper("discipline", "disciplina")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert {:unknown_skill, "disciplina"} in dropped
      assert build.gear.skills == %{hide: 20}
      # остальное на месте
      assert build.levels == sample().levels
      assert build.gear.abilities == %{con: 12}
    end

    # ⚠️ Плата, названная в moduledoc: числа вещей не клипаются кодеком. Правленая
    # руками ссылка с «+99» открывается, а потолок называет ядро.
    test "кодек не режет вписанное число — это дело ядра" do
      %Build{} = build = sample()
      absurd = %Build{build | gear: Gear.new(skills: %{discipline: 99})}

      assert {:ok, %{build: back}} = Encoding.decode(Encoding.encode(absurd))
      assert back.gear.skills == %{discipline: 99}
    end
  end

  describe "оружие в руках (задача 3.5, часть B)" do
    defp with_weapon(fields \\ []) do
      %Build{} = build = sample()

      %Build{
        build
        | gear: Gear.new([abilities: %{con: 12}, weapon: :scimitar, weapon_attack: 5] ++ fields)
      }
    end

    test "оружие и его число доезжают целиком" do
      assert {:ok, %{build: back, dropped: []}} = Encoding.decode(Encoding.encode(with_weapon()))

      assert back.gear.weapon == :scimitar
      assert back.gear.weapon_attack == 5

      # ⚠️ И ни одна часть не уехала в фиты: строка едет под псевдо-слотом
      # `"weapon|…"` уровня 0 в таблице фитов, а собирается обратно в `gear`.
      assert back.feats == sample().feats
      assert back.gear.feats == []
      assert back == with_weapon()
    end

    # 🔴 Задача 3.52 убрала ВТОРОЕ число предмета (усиление), и вот что стало
    # с уже расшаренными ссылками. Число писалось ПОЗИЦИОННО, то есть его несут
    # все ссылки с оружием — даже те, где усиление равно нулю.
    #
    # Второе число СКЛАДЫВАЕТСЯ с первым, а не выбрасывается: сторона капа у них
    # общая всегда (Dan, 19.08.2026: «по механике nwn attack bonus и enchantment
    # bonus должны быть равны в плане капа»), значит сумма даёт то же AB, что
    # давали два терма. Выбрасывание тихо занизило бы такой билд.
    test "старая ссылка с ДВУМЯ числами читается суммой, а не половиной" do
      old_link =
        restring(Encoding.encode(with_weapon()), "weapon|scimitar|5", "weapon|scimitar|2|3")

      assert {:ok, %{build: %Build{} = back, dropped: []}} = Encoding.decode(old_link)
      assert back.gear.weapon == :scimitar
      assert back.gear.weapon_attack == 5

      # И то же самое числом на экране: AB у старой ссылки ровно тот же, что был
      # до правки, — иначе «совместимость не требуется» превратилась бы в тихо
      # изменившийся билд. ⚠️ Владение объявляется вещью: без него оружие
      # в руках не считается вовсе (`Rules.GearWeapon`), и проверка зеленела бы
      # нулём при любой арифметике.
      ruleset = Data.ruleset!(back.ruleset_version)
      %Gear{} = gear = back.gear
      armed = %Build{back | gear: %Gear{gear | feats: [:siala_blade_proficiency]}}

      assert Rules.compute(armed, ruleset).weapon_attack_bonus == 5

      # ⚠️ Отрицательный контроль на ту самую ошибку, которую сложение и
      # закрывает: игнорирование второго числа дало бы 2, а не 5.
      refute back.gear.weapon_attack == 2
    end

    # Вторая половина того же утверждения: новый кодер пишет ОДНО число, то есть
    # запись стала короче ровно на `|<усиление>`. Меряется РАСПАКОВАННЫЙ payload,
    # а не строка кода: длину base64 после zlib округляет упаковка, и «короче»
    # там держалось бы на удаче.
    test "новая ссылка короче старой ровно на второе число" do
      new_link = Encoding.encode(with_weapon())
      old_link = restring(new_link, "weapon|scimitar|5", "weapon|scimitar|5|0")

      assert byte_size(payload(old_link)) - byte_size(payload(new_link)) == byte_size("|0")
      refute payload(new_link) =~ "weapon|scimitar|5|"
    end

    # Переписывает length-prefixed строку в payload'е, поправляя и сам префикс, —
    # в отличие от `tamper/3` рядом, которая держит длину неизменной. Нужна
    # именно здесь: старая запись оружия на два символа длиннее новой.
    defp restring(code, from, to) do
      rewritten =
        String.replace(
          payload(code),
          <<byte_size(from)::8>> <> from,
          <<byte_size(to)::8>> <> to
        )

      "2." <> Base.url_encode64(:zlib.zip(rewritten), padding: false)
    end

    defp payload("2." <> body),
      do: body |> Base.url_decode64!(padding: false) |> :zlib.unzip()

    test "билд БЕЗ оружия кодируется побайтово так же, как раньше" do
      # ⚠️ Пятый раз тот же довод: новая секция в хвосте v2 сменила бы код
      # КАЖДОМУ билду, включая те, где оружия нет, — и «тот же билд = тот же код»
      # перестало бы держаться.
      assert Encoding.encode(sample()) == @frozen_v2

      # Положительный контроль: билд С оружием кодируется иначе — иначе assert
      # выше зеленел бы и на кодеке, который оружие молча теряет.
      refute Encoding.encode(with_weapon()) == Encoding.encode(sample())
    end

    test "версия не выросла, старые ссылки читает тот же парсер" do
      assert Encoding.current_version() == 2
      assert {:ok, %{build: %Build{} = v1}} = Encoding.decode(@frozen_v1)
      assert {:ok, %{build: %Build{} = v2}} = Encoding.decode(@frozen_v2)

      # Ссылка, выпущенная до этой задачи, открывается без оружия — ровно тем
      # билдом, который она описывала.
      assert v1.gear.weapon == nil
      assert v2.gear.weapon == nil
      assert v2.gear.weapon_attack == 0
    end

    # ⚠️ Числа десятичным текстом, а не байтами — ровно затем, чтобы штраф
    # проезжал. У четырёх остальных чисел вещей `byte/1` режет минус в ноль, и это
    # названо в moduledoc как долг; здесь его нет.
    test "штраф с оружия проезжает через ссылку" do
      cursed = with_weapon(weapon_attack: -2)

      assert {:ok, %{build: back}} = Encoding.decode(Encoding.encode(cursed))
      assert back.gear.weapon_attack == -2
    end

    # Оружие, которого справочник больше не знает, теряется ПОИМЁННО — иначе
    # ссылка на снятую со вики запись открылась бы как «оружия и не было».
    test "неизвестное оружие теряется НЕ молча" do
      broken =
        with_weapon()
        |> Encoding.encode()
        # Та же длина, иначе поедет length-prefix строки.
        |> tamper("weapon|scimitar", "weapon|scimitor")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert {:unknown_weapon, "scimitor"} in dropped
      assert build.gear.weapon == nil

      # остальное на месте
      assert build.levels == sample().levels
      assert build.gear.abilities == %{con: 12}
    end

    # ⚠️ Кодек владения НЕ проверяет — это правило ядра
    # (`Rules.illegal_gear_weapon/2`), и повторять его здесь значило бы держать
    # вторую копию. Ровно так же декодер поступает с фитом с вещи и с числами.
    test "оружие без фита владения открывается, а претензию высказывает ядро" do
      assert {:ok, %{build: back}} = Encoding.decode(Encoding.encode(with_weapon()))

      assert back.gear.weapon == :scimitar

      ruleset = BuildCalculator.Data.ruleset!("siala_41")

      assert BuildCalculator.Rules.illegal_gear_weapon(back, ruleset) ==
               [{:scimitar, {:requires_feat, :siala_blade_proficiency}}]
    end
  end

  describe "оружие ВТОРОЙ РУКИ (задача 3.132)" do
    defp with_off_weapon do
      %Build{gear: %Gear{} = gear} = build = with_weapon()
      %Build{build | gear: %Gear{gear | off_hand_weapon: :mace, off_hand_weapon_attack: 2}}
    end

    test "вторая рука и её число доезжают целиком, независимо от главной" do
      build = with_off_weapon()

      assert {:ok, %{build: back, dropped: []}} = Encoding.decode(Encoding.encode(build))

      assert back.gear.weapon == :scimitar
      assert back.gear.weapon_attack == 5
      assert back.gear.off_hand_weapon == :mace
      assert back.gear.off_hand_weapon_attack == 2
      assert back == build
    end

    # 🔴 Билд без второй руки (`with_weapon()`, из соседнего describe) —
    # то есть КАЖДАЯ уже расшаренная ссылка — кодируется так же, как до
    # этой задачи: byte-for-byte проверяют `@frozen_v1`/`@frozen_v2` рядом
    # в этом файле, которых задача не тронула и которые по-прежнему
    # проходят. Здесь — обратная сторона, положительный контроль: билд СО
    # второй рукой обязан кодироваться ИНАЧЕ, иначе строка терялась бы
    # молча и assert выше зеленел бы у кодека, который её просто не пишет.
    test "билд со второй рукой кодируется иначе, чем без неё" do
      refute Encoding.encode(with_off_weapon()) == Encoding.encode(with_weapon())
    end

    test "старая ссылка (до задачи 3.132) открывается без второй руки" do
      assert {:ok, %{build: %Build{} = back}} = Encoding.decode(@frozen_v2)

      assert back.gear.off_hand_weapon == nil
      assert back.gear.off_hand_weapon_attack == 0
    end

    # ⚠️ Числа десятичным текстом, как у главной руки — минус проезжает целиком.
    test "штраф со второй руки проезжает через ссылку" do
      %Build{gear: %Gear{} = gear} = cursed = with_off_weapon()
      cursed = %Build{cursed | gear: %Gear{gear | off_hand_weapon_attack: -2}}

      assert {:ok, %{build: back}} = Encoding.decode(Encoding.encode(cursed))
      assert back.gear.off_hand_weapon == :mace
      assert back.gear.off_hand_weapon_attack == -2
    end

    # Оружие второй руки, которого справочник не знает, теряется ПОИМЁННО —
    # та же причина, что у главной: ссылка на снятое с вики оружие иначе
    # открылась бы как «второй руки и не было».
    test "неизвестное оружие второй руки теряется НЕ молча" do
      broken =
        with_off_weapon()
        |> Encoding.encode()
        # Та же длина, иначе поедет length-prefix строки (см. `tamper/3`).
        |> tamper("offweapon|mace", "offweapon|macx")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert {:unknown_weapon, "macx"} in dropped
      assert build.gear.off_hand_weapon == nil

      # Главная рука и остальное — на месте.
      assert build.gear.weapon == :scimitar
      assert build.levels == sample().levels
    end

    # ⚠️ Кодек владения и хвата НЕ проверяет здесь тоже — правило ядра
    # (`Rules.illegal_gear_weapon/2`, которое с задачи 3.132 обходит ОБЕ
    # руки), и повторять его в кодеке значило бы держать вторую копию.
    test "вторая рука без владения открывается, а претензию высказывает ядро" do
      assert {:ok, %{build: back}} = Encoding.decode(Encoding.encode(with_off_weapon()))

      ruleset = Data.ruleset!("siala_41")

      assert {:mace, {:requires_feat, :siala_hammer_proficiency}} in Rules.illegal_gear_weapon(
               back,
               ruleset
             )
    end
  end

  describe "выбор у выданного фита (задача 3.26)" do
    # `weapon_of_choice` — единственный выданный фит с выбором в обоих
    # ruleset'ах, и выдаёт его Мастер оружия на 1-м классовом уровне. Билд ниже
    # берёт его на 5-м персонажном, чтобы уровень выдачи заведомо не совпадал
    # ни с `0` псевдо-слотов вещей, ни с 1-м уровнем.
    defp with_granted_choice do
      %Build{} = build = sample()

      %Build{build | levels: sample().levels ++ [:weapon_master]}
      |> Build.put_granted_choice(7, :weapon_of_choice, :scimitar)
    end

    test "выбор выдачи доезжает целиком и не уходит в слоты" do
      build = with_granted_choice()

      assert {:ok, %{build: back, dropped: []}} = Encoding.decode(Encoding.encode(build))

      assert back.granted_choices == %{7 => %{weapon_of_choice: :scimitar}}

      # ⚠️ И ни одна часть не уехала в слоты: строка едет псевдо-слотом
      # `"granted"`, а собирается обратно в `granted_choices`. Иначе выдача стала
      # бы неотличима от пика, то есть заняла бы слот, которого не занимает.
      assert back.feats == sample().feats
      assert back == build
    end

    test "билд БЕЗ выбора выдачи кодируется побайтово так же, как раньше" do
      # ⚠️ Шестой раз тот же довод: новая секция в хвосте v2 сменила бы код
      # КАЖДОМУ билду, включая те, где выданного выбора нет. Ровно это и значит
      # «уже расшаренная ссылка продолжает открываться тем же билдом».
      assert Encoding.encode(sample()) == @frozen_v2

      # Положительный контроль: код С выбором выдачи другой — иначе assert выше
      # зеленел бы и на кодеке, который выбор молча теряет.
      refute Encoding.encode(with_granted_choice()) == Encoding.encode(sample())
    end

    test "версия не выросла, а старые ссылки открываются без выбора выдачи" do
      assert Encoding.current_version() == 2

      assert {:ok, %{build: %Build{} = v1}} = Encoding.decode(@frozen_v1)
      assert {:ok, %{build: %Build{} = v2}} = Encoding.decode(@frozen_v2)

      # Ссылка, выпущенная до этой задачи, открывается ровно тем билдом, который
      # описывала: выбора выдачи в ней нет, и ядро считает её как считало.
      assert v1.granted_choices == %{}
      assert v2.granted_choices == %{}
    end

    # ⚠️ Ключ `"granted"` намеренно НЕ настоящий слот: попади он в белый список,
    # клик из браузера смог бы положить фит в слот, которого ни один уровень не
    # выдаёт. Заодно это и есть плата за приём: старая сборка увидит `unknown_slot`.
    test "«granted» не является слотом для Ids" do
      ruleset = Data.ruleset!("siala_41")

      assert Ids.fetch_slot(ruleset, "granted") == :error
      assert Ids.fetch_slot(ruleset, "general") == {:ok, :general}
    end

    test "значение, которого нет в справочнике, роняет строку и говорит об этом" do
      broken =
        with_granted_choice()
        |> Encoding.encode()
        # Та же длина, иначе поедет length-prefix строки.
        |> tamper("weapon_of_choice|scimitar", "weapon_of_choice|scimitor")

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(broken)
      assert dropped == [{:unknown_choice, "weapon_of_choice|scimitor"}]
      assert build.granted_choices == %{}

      # остальное на месте
      assert build.levels == with_granted_choice().levels
      assert build.feats == sample().feats
    end
  end

  describe "hostile input" do
    test "garbage never raises" do
      for code <- ["", "1.", "1.!!!", "1.aaaa", "nonsense", "..", "1.MTIz"] do
        assert {:error, _reason} = Encoding.decode(code)
      end
    end

    test "a schema version we do not have is refused by name" do
      assert {:error, :unknown_version} = Encoding.decode("7.abcdef")
    end

    test "a non-string is refused" do
      assert {:error, :malformed} = Encoding.decode(nil)
      assert {:error, :malformed} = Encoding.decode(%{})
    end

    test "an absurdly long code is refused before it is inflated" do
      assert {:error, :too_long} = Encoding.decode("1." <> String.duplicate("a", 5000))
    end

    test "truncating a valid code does not raise" do
      code = Encoding.encode(sample())
      short = binary_part(code, 0, div(byte_size(code), 2))

      assert {:error, _reason} = Encoding.decode(short)
    end
  end

  describe "ids that the data no longer knows" do
    test "are dropped and reported rather than turned into atoms" do
      # Hand-built payload naming a class that has never existed.
      payload =
        <<1::8>> <>
          str("siala_41") <>
          str("") <>
          str("") <>
          <<0::8>> <>
          <<1::8>> <>
          str("nonexistent_class") <>
          <<1::8, 0::8, 3::8>> <>
          <<0::8>> <>
          <<0::16>> <>
          <<0::16>> <>
          <<0::8>> <>
          <<0::16>>

      code = "1." <> Base.url_encode64(:zlib.zip(payload), padding: false)

      assert {:ok, %{build: build, dropped: dropped}} = Encoding.decode(code)
      assert build.levels == []
      assert {:unknown_class, "nonexistent_class"} in dropped

      # And no atom was minted for it — `String.to_atom/1` on user input is the
      # memory leak this codec exists to avoid (AGENTS.md).
      assert_raise ArgumentError, fn -> String.to_existing_atom("nonexistent_class") end
    end
  end

  defp str(value), do: <<byte_size(value)::8, value::binary>>
end
