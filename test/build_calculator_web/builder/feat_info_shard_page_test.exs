defmodule BuildCalculatorWeb.Builder.FeatInfoShardPageTest do
  @moduledoc """
  `Labels.feat_info/2` → `shard_page` и `Labels.feat_info_shown?/1` — поп-ап
  одиннадцати фитов шарда, у которых нет страницы на Fandom (задача 4.71,
  слово Dan 04.10.2026: «Ок, давай добавим попап»).

  Страница шарда дословно, блоками (`WikiBlocks.blocks/1`): «Особенности»,
  потом остальные лейблы строкой «Лейбл: значение», потом разделы под своими
  заголовками. Не показываются: раздел «Возможность взятия фита» — список
  бонусных слотов неполон (`AK1`: Паладин), и лейбл «требуется для умения»
  (граф, 4.70) — оба решены в загрузчике одним списком (`@not_feat_text`).
  """
  use ExUnit.Case, async: true

  alias BuildCalculator.Data
  alias BuildCalculatorWeb.Builder.Labels

  @eleven ~w(instinctive_throw riding_sprint shades_feat siala_axe_proficiency
             siala_blade_proficiency siala_hammer_proficiency siala_polearm_proficiency
             siala_ranged_proficiency siala_spell_school_focus smile_of_death teleportation)a

  setup_all do
    Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
    %{siala: Data.ruleset!("siala_41"), vanilla: Data.ruleset!("vanilla")}
  end

  setup do
    Gettext.put_locale(BuildCalculatorWeb.Gettext, "ru")
    :ok
  end

  defp texts(blocks),
    do: Enum.flat_map(blocks, &Map.get(&1, :items, [Map.get(&1, :text)]))

  test "Instinctive throw — «Особенности», лейблы с «Пометкой», раздел «Общие» блоками",
       %{siala: siala} do
    info = Labels.feat_info(siala, :instinctive_throw)

    assert [
             %{kind: "p", text: special},
             %{kind: "p", text: "Звезда беспорядочности: " <> _},
             %{kind: "p", text: "Звезда ошеломления: " <> _},
             %{kind: "p", text: "Пометка: Использовать умение можно с 15 уровня Монаха."},
             %{kind: "h", text: "Общие"},
             %{kind: "ul", items: [delay]},
             %{kind: "pre", text: "27 - (лвл монка - 14) раундов"},
             %{kind: "ul", items: [sling, temple]}
           ] = info.shard_page

    assert special =~ "специальный бросок особыми снарядами"
    assert delay =~ "задержка в размере:"

    # Разметка вики прочитана в текст: жирный — без апострофов.
    assert sling =~ "умения Instinctive Throw особые снаряды Звезда Беспорядочности"
    refute sling =~ "'''"
    assert temple =~ "в любом храме"

    # Не «изменён на Сиале»: ванильного фита, который можно было бы изменить, нет.
    refute info.siala_changed?
    assert info.siala_notes == []
    assert info.description == nil
    assert info.source_url == nil
    assert Labels.feat_info_shown?(info)
  end

  # 🔴 «Возможность взятия фита» не показывается: список называет Воина,
  # Рейнджера, Мастера оружия и Чемпиона Торма и молчит о Паладине (AK1).
  test "владение — «Общая информация» с четырьмя группами, без списка слотов", %{siala: siala} do
    info = Labels.feat_info(siala, :siala_axe_proficiency)

    assert [
             %{kind: "h", text: "Общая информация"},
             %{kind: "p", text: intro},
             %{kind: "ol", items: [one, ten, twenty, thirty]}
           ] = info.shard_page

    assert intro =~ "Уникальное умение Сиалы"

    # Одиночный перенос строки на странице — пробел, как у MediaWiki.
    assert intro =~ "остальные виды оружия. Все оружие поделено на четыре группы:"
    assert one =~ "Серпы (2-6 20/х2 одноручное, урон - режущий)"
    assert one =~ "с 1-го уровня"
    assert ten =~ "с 10-го уровня"
    assert twenty =~ "с 20-го уровня"
    assert thirty =~ "с 30-го уровня"

    text = Enum.join(texts(info.shard_page), "\n")
    refute text =~ "Возможность взятия"
    refute text =~ "Чемпион Торма"
    refute text =~ "доп фитах"
  end

  test "все пять владений — один и тот же вид, ни у одного нет списка слотов", %{siala: siala} do
    for id <- ~w(siala_axe_proficiency siala_blade_proficiency siala_hammer_proficiency
                 siala_polearm_proficiency siala_ranged_proficiency)a do
      page = Labels.feat_info(siala, id).shard_page

      assert [%{kind: "h", text: "Общая информация"}, %{kind: "p"}, %{kind: "ol", items: items}] =
               page,
             "#{id}"

      assert length(items) == 4, "#{id}"
      refute Enum.join(texts(page)) =~ "Мастер оружия", "#{id}"
    end
  end

  # Teleportation и Shades — разделов нет, только «Особенности» и лейблы.
  test "Teleportation — без разделов: три абзаца «Особенностей» и два лейбла", %{siala: siala} do
    info = Labels.feat_info(siala, :teleportation)

    assert [
             %{kind: "p", text: first},
             %{kind: "p", text: "Волшебник так же может использовать посох" <> _},
             %{kind: "p", text: "Перемещение нельзя использовать" <> _},
             %{kind: "p", text: "Количество: Количество прыжков ограничено" <> _},
             %{kind: "p", text: "Общая дистанция: 5 метров * Уровень Волшебника."}
           ] = info.shard_page

    assert first =~ "магические и боевые посохи"
    refute Enum.any?(info.shard_page, &(&1.kind == "h"))
    assert Labels.feat_info_shown?(info)
  end

  # Единственная `siala_note` среди одиннадцати — это и есть раздел страницы:
  # под «изменено на Сиале» она повторила бы раздел вторым разом.
  test "фокусировки на школы — раздел страницы, без «изменено на Сиале»", %{siala: siala} do
    # Положительный контроль: у записи правка шарда есть.
    assert Enum.any?(
             siala.feats[:siala_spell_school_focus].siala_changes,
             &(&1["what"] == "siala_note")
           )

    info = Labels.feat_info(siala, :siala_spell_school_focus)

    assert [%{kind: "h", text: "изменения в магии на Сиале"} | lists] = info.shard_page
    assert length(lists) == 4
    assert Enum.all?(lists, &(&1.kind == "ul"))
    assert hd(hd(lists).items) =~ "школа Conjuration"
    refute info.siala_changed?
    assert info.siala_notes == []
  end

  test "перепись: страница у всех одиннадцати и ни у одного фита больше", %{
    siala: siala,
    vanilla: vanilla
  } do
    for {name, ruleset} <- [siala: siala, vanilla: vanilla],
        {id, feat} <- ruleset.feats do
      info = Labels.feat_info(ruleset, id)

      if name == :siala and id in @eleven do
        assert info.shard_page != [], "#{id}"
        assert Labels.feat_info_shown?(info), "#{id}"
      else
        assert info.shard_page == [], "#{name} #{id}"

        # Ворота у всех остальных — прежние: есть описание Fandom.
        assert Labels.feat_info_shown?(info) == (feat.description != nil), "#{name} #{id}"
      end
    end

    # Положительный контроль: у ванили фиты есть, у всех есть описание.
    assert map_size(vanilla.feats) > 0
    assert Enum.all?(vanilla.feats, fn {_id, feat} -> feat.description != nil end)
  end

  test "пустое и неизвестное — поп-апа нет", %{siala: siala} do
    refute Labels.feat_info_shown?(Labels.feat_info(siala, nil))
    refute Labels.feat_info_shown?(Labels.feat_info(siala, :not_a_real_feat))
  end
end
