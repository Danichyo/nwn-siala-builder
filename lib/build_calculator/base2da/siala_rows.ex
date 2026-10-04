defmodule BuildCalculator.Base2da.SialaRows do
  @moduledoc """
  Строки таблиц хака Сиалы, которые сверка `mix hak2da.diff` (задача 4.49)
  не может сопоставить по имени, — явной таблицей.

  Имена у этих строк — из кастомного `.tlk` шарда, которого в выгрузке нет,
  а в базовой игре таких строк нет вовсе (`Base2da.Source`, moduledoc). Каждая
  строка названа **меткой**, и метка сверяется (`Base2da.Ids`): шард сдвинет
  строку — сверка упадёт, а не сопоставит чужую.

  ⚠ `name` — **наша подпись** для отчёта, собранная из метки строки, а не имя
  из игры: игра называет эти фиты по-русски, словами своего `.tlk`. У строк
  фокуса на навык подпись повторяет форму базовых имён («Skill Focus (Ride)»),
  потому что по скобке сверка читает значение выбора.

  Откуда сопоставление:

    * 2001–2005 — пять владений оружием Сиалы (`docs/hak_diff_feats.md` §2;
      та же таблица в `feat_requirements_hak_test.exs`, сверенная с группами
      `siala_proficiency_group` у всех 38 оружий);
    * 2006, 2007, 2009, 2017, 1950 — фиты Сиалы с тем же `Constant`, что наш id
      (`docs/hak_diff_feats.md` §2);
    * 2019–2022 — новые значения выбора у `Skill focus` / `Epic skill focus`
      (Верховая езда и Алхимия, замеры `AB1`/`AB2`);
    * 754 — 🔴 **«Дух Сиалы»**, а не ступень Epic toughness: строка подписана
      `FEAT_EPIC_TOUGHNESS_1`, но это отдельный фит, выданный всем на 1-м уровне
      (решение Dan 02.10.2026, задача 4.52). Нашего id у него нет — в модели он
      `character.spirit_of_siala` (`siala_41/overrides.json`), а не фит;
    * 944 — **прежняя строка Brew Potion**: хак вывел её из оборота, поставив
      `GrantedOnLevel 99` во всех своих `cls_feat_*`, и завёл рядом строку 2018
      (`Constant FEAT_BREW_POTION_2`, `ALLCLASSESCANUSE 1`, Lore 4 —
      `docs/hak_diff_feats.md` §5). Без этой строки в таблице каноническим
      для семейства стало бы мёртвое «было», а не живое «стало»;
    * 2008 — `FEAT_CHARGE`: таран верхом (страница Сиалы «Верховая езда» —
      «максимального Чарджа верхом на лошади с копьем»); в справочнике его нет,
      на печать он не влияет.
  """

  @feat %{
    754 => %{
      label: "FEAT_EPIC_TOUGHNESS_1",
      id: nil,
      name: "«Дух Сиалы»",
      group: "spirit_of_siala"
    },
    944 => %{
      label: "FEAT_BREW_POTION",
      id: nil,
      name: "Brew Potion (строка базы, снятая хаком)",
      group: "siala_retired_rows"
    },
    1950 => %{label: "Smile_of_death", id: :smile_of_death, name: "Smile of Death"},
    2001 => %{label: "Hammers", id: :siala_hammer_proficiency, name: "Hammers"},
    2002 => %{label: "Axes", id: :siala_axe_proficiency, name: "Axes"},
    2003 => %{label: "Polearms", id: :siala_polearm_proficiency, name: "Polearms"},
    2004 => %{label: "Bows", id: :siala_ranged_proficiency, name: "Bows"},
    2005 => %{label: "Swords", id: :siala_blade_proficiency, name: "Swords"},
    2006 => %{label: "InstinvtiveThrow", id: :instinctive_throw, name: "Instinctive Throw"},
    2007 => %{label: "Riding_Sprint", id: :riding_sprint, name: "Riding Sprint"},
    2008 => %{label: "Charge", id: nil, name: "Charge (FEAT_CHARGE)", group: "siala_riding"},
    2009 => %{label: "FEAT_PRESTIGE_SPELL_SHADES", id: :shades_feat, name: "Shades"},
    2017 => %{label: "FEAT_WIZARD_TELEPORT", id: :teleportation, name: "Teleportation"},
    2019 => %{label: "FEAT_SKILL_FOCUS_RIDE", id: :skill_focus, name: "Skill Focus (Ride)"},
    2020 => %{
      label: "FEAT_EPIC_SKILL_FOCUS_RIDE",
      id: :epic_skill_focus,
      name: "Epic Skill Focus (Ride)"
    },
    2021 => %{label: "FEAT_SKILL_FOCUS_ALCHEMY", id: :skill_focus, name: "Skill Focus (Alchemy)"},
    2022 => %{
      label: "FEAT_EPIC_SKILL_FOCUS_ALCHEMY",
      id: :epic_skill_focus,
      name: "Epic Skill Focus (Alchemy)"
    }
  }

  # Алхимия — 29-й навык движка Сиалы, свой `Constant` SKILL_ALCHEMY
  # (`siala_41/skills.json` → alchemy, сверка 3.129).
  @skills %{28 => %{label: "Alchemy", id: :alchemy, name: "Alchemy"}}

  # Stream of Flame — заклинание Сиалы на строке 191, где у базовой игры Wall
  # of Fire (та переехала на строку 843 с кругом друида 5); страница Сиалы
  # «Stream of Flame» (revid 18219), слой `siala_41/spells.json`.
  #
  # Строка 50 — «Отражение (Reflection)» (`.tlk` шарда, строка 16781206) на месте
  # базового Endure Elements: страница Сиалы «Отражение» (revid 20028) — «заменяет
  # собой заклинание Endure elements». Наш id прежний (`endure_elements`: ссылки
  # хранят id), имя и иконку переписывает слой `siala_41/spells.json` (задача 4.58).
  # До 4.58 строка намеренно не была названа — сопоставить её значило бы спрятать
  # находку про имя. Теперь имя у строк этой таблицы сверяется с меткой
  # (`CompareOther`, поле `name`): уберёшь запись слоя — вернётся находка без вида.
  @spells %{
    50 => %{label: "Reflection", id: :endure_elements, name: "Reflection"},
    191 => %{label: "Stream_of_flame", id: :stream_of_flame, name: "Stream of Flame"}
  }

  @doc "Явные строки для `Base2da.Diff.run/4` (`row_overrides`)."
  @spec row_overrides() :: %{String.t() => map()}
  def row_overrides, do: %{"feat" => @feat, "skills" => @skills, "spells" => @spells}
end
