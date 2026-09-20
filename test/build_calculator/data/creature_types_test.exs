defmodule BuildCalculator.Data.CreatureTypesTest do
  @moduledoc """
  Guards the three dictionaries a repeatable feat chooses from, as committed.

  These files exist because `Favored enemy` picks a racial type, `Spell focus`
  picks a school and `Epic energy resistance` picks a damage type, and none of
  those sets was in the snapshot at all. What is pinned here is the arithmetic
  the wiki states in words — 24 of 25, only `ooze` — because that is the one
  claim a regenerated file could quietly break, and because "the list looks
  plausible" is not a check.
  """

  use ExUnit.Case, async: true

  alias BuildCalculator.Rules.FeatChoices

  # Не строка: имя домен-широких ворот принадлежит ядру, и вписать его сюда
  # руками значило бы завести вторую копию, которая молча разойдётся с первой.
  @gate Atom.to_string(FeatChoices.domain_gate())

  @creature_types "priv/rules/vanilla/creature_types.json" |> File.read!() |> Jason.decode!()
  @spell_schools "priv/rules/vanilla/spell_schools.json" |> File.read!() |> Jason.decode!()
  @energy_types "priv/rules/vanilla/energy_types.json" |> File.read!() |> Jason.decode!()
  @feats "priv/rules/vanilla/feats.json" |> File.read!() |> Jason.decode!()

  defp types, do: @creature_types["types"]
  defp schools, do: @spell_schools["schools"]

  describe "creature types" do
    # The sentence on `Favored enemy`, in numbers: "There are 24 favored enemy
    # races available; of the 25 standard races, only ooze cannot be selected."
    test "25 types, 24 of them selectable, and the one exception is ooze" do
      assert length(types()) == 25
      assert Enum.count(types(), & &1["favored_enemy"]) == 24

      assert Enum.reject(types(), & &1["favored_enemy"]) |> Enum.map(& &1["id"]) == ["ooze"]
    end

    test "the rule block carries the sentence the count came from" do
      rule = @creature_types["_chosen_by"]

      assert rule["feat"] == "favored_enemy"
      assert rule["available"] == 24
      assert rule["total"] == 25
      assert rule["excluded"] == ["ooze"]
      assert rule["quote"] =~ "only [[ooze]] cannot be selected"
      assert rule["source"]["page"] == "Favored enemy"
    end

    # ⚠️ Здесь ворота НАРОЧНО именные, в отличие от школ, и это не забытая
    # правка. Фраза, из которой они взяты, — про фит, а не про значение:
    # «only ooze cannot be selected [as a favored enemy]». Ни одна страница
    # не говорит, что ooze перестал быть расой, поэтому домен-широкие ворота
    # были бы утверждением, которого нет в источнике (CLAUDE.md §3).
    #
    # Плата за это осознанная: второй фит, выбирающий тип существа, придёт
    # без ворот, и сторож в `feat_choices_test.exs` покраснеет, пока человек
    # не прочитает источник. Покраснеть — верный исход; молча выдать ooze —
    # неверный.
    test "у типов существ ворота именные, а домен-широких нет — и это решение" do
      assert Enum.all?(types(), &Map.has_key?(&1, "favored_enemy"))
      assert @creature_types["_chosen_by"]["gate"] == "favored_enemy"

      refute Enum.any?(types(), &Map.has_key?(&1, @gate)),
             "домен-широкие ворота у типов существ утверждали бы то, чего источник не говорит"
    end

    # `Subrace` sits in Category:Races and is an article about races. If it ever
    # reappears the count breaks first, but naming it here says why it is absent.
    test "the article filed under the category is not one of the types" do
      refute "subrace" in Enum.map(types(), & &1["id"])
    end

    # The exclusion carries its reason, and the reason is on ooze's own page
    # rather than on the feat's: added by an expansion after the feat's list was
    # fixed. A bare `false` would lose that.
    test "the excluded type explains itself in the wiki's own words" do
      ooze = Enum.find(types(), &(&1["id"] == "ooze"))

      assert ooze["note"] =~ "not an option for a ranger's"
      assert ooze["source"]["page"] == "Ooze"
    end

    test "the seven playable races are among the types" do
      ids = Enum.map(types(), & &1["id"])

      for race <- ~w(dwarf elf gnome half_elf half_orc halfling human) do
        assert race in ids, race
      end
    end
  end

  describe "spell schools" do
    test "eight schools plus universal, which cannot be chosen" do
      assert length(schools()) == 9
      assert Enum.count(schools(), & &1[@gate]) == 8

      assert Enum.reject(schools(), & &1[@gate]) |> Enum.map(& &1["id"]) == ["universal"]
    end

    test "the eight are the ones the game names" do
      assert schools()
             |> Enum.filter(& &1[@gate])
             |> Enum.map(& &1["id"])
             |> Enum.sort() ==
               ~w(abjuration conjuration divination enchantment evocation illusion necromancy transmutation)
    end

    # ⚠️ Имя флага — это КОНТРАКТ с ядром, а не украшение файла. Ядро читает
    # домен-широкие ворота по одному зарезервированному имени; словарь, который
    # назовёт их иначе, отдаст полный список значений, и «universal» вернётся
    # в школы молча. Раньше здесь стояло `spell_focus` — имя фита, — и оно
    # работало ровно для одного фита из четырёх.
    test "ворота названы тем именем, которое читает ядро" do
      assert Enum.all?(schools(), &Map.has_key?(&1, @gate)),
             "не у каждой школы есть флаг #{@gate}"

      refute Enum.any?(schools(), &Map.has_key?(&1, "spell_focus")),
             "остались именные ворота spell_focus: они перекрывают общие и разойдутся с ними"

      assert @spell_schools["_chosen_by"]["gate"] == @gate
    end

    # Two independent pages: universal's own page says what it is, and the epic
    # feat's icon strip enumerates eight variants without it.
    test "the exclusion is stated on universal's page and corroborated by the feat's" do
      rule = @spell_schools["_chosen_by"]

      assert rule["quote"] =~ "not truly a [[spell school]]"
      assert rule["source"]["page"] == "Universal"
      assert length(rule["corroborated_by"]["variants"]) == 8
      assert rule["corroborated_by"]["source"]["page"] == "Epic spell focus"
    end

    # `Spell school list (bard)` and its five siblings are in the category too.
    test "the six list articles are not schools" do
      for id <- Enum.map(schools(), & &1["id"]) do
        refute id =~ "spell_school_list", id
      end
    end
  end

  describe "energy types" do
    test "the five damage types, none excluded" do
      assert Enum.map(@energy_types["types"], & &1["id"]) ==
               ~w(acid cold electrical fire sonic)

      assert @energy_types["_chosen_by"]["excluded"] == []
    end

    # There is no category and no page per type — the set is a sentence, so the
    # only available check is that the two pages carrying it agree.
    test "both pages that list the types are recorded" do
      rule = @energy_types["_chosen_by"]

      assert rule["source"]["page"] == "Resist energy"
      assert rule["corroborated_by"]["source"]["page"] == "Epic energy resistance"
    end

    # Ворот нет ВОВСЕ, и это тоже ответ: обе страницы называют одни и те же
    # пять, ни одна ничего не исключает. Проставить `selectable: true` пятью
    # строками значило бы записать правило, которого никто не писал; словарь
    # без флагов ядро отдаёт целиком, что здесь и верно.
    test "у типов урона ворот нет ни тех, ни других" do
      for type <- @energy_types["types"] do
        refute Map.has_key?(type, @gate), type["id"]
        refute Map.has_key?(type, "epic_energy_resistance"), type["id"]
      end

      assert @energy_types["_chosen_by"]["gate"] == nil
    end
  end

  describe "the feats that point at them" do
    defp feat(id), do: Enum.find(@feats, &(&1["id"] == id))

    test "every named choice domain has the dictionary it names" do
      domains =
        for f <- @feats, r = f["repeatable"], r["choice"], do: r["choice"]

      # `weapon` is deliberately dictionary-less: weapons are not modelled at
      # all, so the domain is named honestly and resolves to nothing until an
      # armoury exists (CLAUDE.md §3).
      for domain <- Enum.uniq(domains) -- ["weapon"] do
        assert File.exists?("priv/rules/vanilla/#{domain}s.json") or
                 File.exists?("priv/rules/vanilla/#{domain}_types.json") or
                 File.exists?("priv/rules/vanilla/#{domain}.json"),
               "no dictionary for choice domain #{domain}"
      end
    end

    test "favored enemy chooses a creature type" do
      assert feat("favored_enemy")["repeatable"]["choice"] == "creature_type"
    end

    test "the focus family must choose something new each time" do
      for id <- ~w(spell_focus greater_spell_focus skill_focus weapon_focus improved_critical) do
        assert feat(id)["repeatable"]["distinct"] == true, id
      end
    end

    # ⚠ The counterexample. Ten helpings of the same damage type is how its cap
    # is reached, so "a repeat must differ" is not a universal rule.
    test "epic energy resistance may take the same type again" do
      assert feat("epic_energy_resistance")["repeatable"]["distinct"] == false
    end

    test "a repeat the source never qualifies carries no `distinct` at all" do
      refute Map.has_key?(feat("favored_enemy")["repeatable"], "distinct")
    end

    # The line this whole file defends: a decision needs a quote, and an
    # undecided feat gets a quote and no decision.
    test "every repeatable feat quotes the page it was read from" do
      for f <- @feats, r = f["repeatable"] do
        assert is_binary(r["quote"]) and r["quote"] != "", f["id"]
        assert r["source"]["page"], f["id"]
      end
    end

    test "the undecided are quoted but never given a choice" do
      undecided = for f <- @feats, f["repeatable_raw"], do: f

      assert length(undecided) == 12

      for f <- undecided do
        assert is_binary(f["repeatable_raw"]["quote"]), f["id"]
        refute f["repeatable"], "#{f["id"]} is both decided and undecided"
      end
    end

    test "the counts of the three answers" do
      assert Enum.count(@feats, & &1["repeatable"]) == 25
      assert Enum.count(@feats, & &1["repeatable_raw"]) == 12
      assert Enum.count(@feats, &(&1["prereqs"] || %{})["same_choice_as"]) == 9
    end

    # The pages that discuss repetition in order to deny it get no key, which is
    # the same as never having been read — so the reasons live in the module and
    # this pins that they stayed out of the data.
    test "the feats whose pages deny repetition carry no key" do
      for id <- ~w(armor_skin epic_prowess extra_turning epic_shadowlord) do
        refute feat(id)["repeatable"], id
        refute feat(id)["repeatable_raw"], id
      end
    end
  end
end
