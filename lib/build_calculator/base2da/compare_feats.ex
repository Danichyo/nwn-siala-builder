defmodule BuildCalculator.Base2da.CompareFeats do
  @moduledoc """
  Сверка фитов с `feat.2da` (задача 4.5): требования, повторяемость и то,
  какой класс может взять фит на своём уровне.

  ## Семейство против строки

  У нас один id на семейство (`weapon_focus`), в `feat.2da` — строка на каждое
  оружие или ступень. Требования семейства берутся с **канонической строки**:

    * у семейства выбора (есть `MASTERFEAT`) — с самой частой формы среди строк
      первой ступени: особые строки (`Weapon Focus (creature)`, `Skill Focus
      (Animal Empathy)` с `ALLCLASSESCANUSE 0`) не перекрывают правило для
      сорока остальных;
    * у семейства ступеней — с первой ступени.

  ## Требование-ступень

  🔴 `PREREQFEAT` и `OrReqFeat` указывают на **строку**, а строка бывает старшей
  ступенью: `Improved Sneak Attack` требует `Sneak Attack (+8d6)`, `Mighty Rage` —
  `Greater Rage`. У нас такие требования записаны уровнем класса (`rogue 15`,
  `barbarian 20`). Поэтому строка-требование засчитывается, если её семейство
  есть у нас и это первая ступень — **или** если наш уровень класса её выдаёт
  (`cls_feat_*`, List 3). Иначе сверка сравнивала бы «ступень» с «семьёй»
  и находила ложные расхождения.
  """

  alias BuildCalculator.Base2da.{Report, Tally}
  alias BuildCalculator.GameFiles.TwoDA
  alias BuildCalculator.Rules.FeatSlots

  @abilities [
    {"MINSTR", :str},
    {"MINDEX", :dex},
    {"MININT", :int},
    {"MINWIS", :wis},
    {"MINCON", :con},
    {"MINCHA", :cha}
  ]
  @proficiencies ~w(weapon_proficiency_simple weapon_proficiency_martial weapon_proficiency_exotic
                    weapon_proficiency_druid weapon_proficiency_monk weapon_proficiency_rogue
                    weapon_proficiency_wizard weapon_proficiency_elf weapon_proficiency_creature)a

  @spec run(map()) :: [Tally.t()]
  def run(ctx), do: [requirements(ctx), repeatable(ctx), availability(ctx)]

  # --------------------------------------------------------- requirements --

  defp requirements(ctx) do
    tally = Tally.new(:feats, "Фиты: требования (feat.2da)")

    tally =
      ctx.families
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce(tally, fn {family, _rows}, tally ->
        family_requirements(tally, ctx, family)
      end)

    tally
    |> unmapped_rows(ctx)
    |> unmapped_ids(ctx)
  end

  defp family_requirements(tally, ctx, family) do
    feat = ctx.ruleset.feats[family]
    {row, base} = canonical(ctx, family)
    prereqs = feat.prereqs || %{}
    at = "feat.2da:#{row} #{TwoDA.get(ctx.feat, row, "LABEL")}"
    ours_at = "feats.#{family}.prereqs"
    granted_only = granted_only?(ctx, family)

    attrs = fn field, column ->
      [subject: family, field: field, base_at: "#{at}.#{column}", ours_at: ours_at] ++
        if granted_only,
          do: [
            kind: :b,
            note:
              "Фит только выдаётся классом (ни в одном cls_feat нет List 0/1/2) — требования к выбору не применяются."
          ],
          else: []
    end

    ours_abilities =
      Map.new(prereqs["abilities"] || %{}, fn {k, v} -> {String.to_existing_atom(k), v} end)

    tally
    |> Tally.check(base.bab, prereqs["base_attack_bonus"], attrs.("bab", "MINATTACKBONUS"))
    |> Tally.check(
      base.abilities,
      ours_abilities,
      attrs.("abilities", "MINSTR…MINCHA")
      |> Keyword.put(:same, &abilities_agree?(ctx, family, &1, &2))
    )
    |> Tally.check(
      base.spell_level,
      prereqs["casts_spell_level"] || prereqs["caster_level"],
      attrs.("spell_level", "MINSPELLLVL")
    )
    |> skills(ctx, family, base, prereqs, attrs)
    |> and_feats(ctx, family, base, prereqs, attrs)
    |> or_feats(ctx, family, base, prereqs, attrs)
    |> class_gate(family, base, prereqs, attrs)
    |> Tally.check(
      base.max_level,
      prereqs["max_character_level"],
      attrs.("max_level", "MaxLevel")
    )
    |> Tally.check(
      base.min_fort,
      get_in(prereqs, ["save_bonus", "fortitude"]),
      attrs.("min_fort", "MinFortSave")
    )
    |> Tally.check(
      base.epic,
      feat.epic?,
      attrs.("epic", "PreReqEpic") |> Keyword.put(:ours_at, "feats.#{family}.epic?")
    )
  end

  defp skills(tally, ctx, family, base, prereqs, attrs) do
    if choice_family?(ctx, family) do
      tally
    else
      ours = Map.new(prereqs["skills"] || %{}, fn {k, v} -> {String.to_existing_atom(k), v} end)
      Tally.check(tally, base.skills, ours, attrs.("skills", "REQSKILL/ReqSkillMinRanks"))
    end
  end

  defp and_feats(tally, ctx, family, base, prereqs, attrs) do
    ours = our_feats(prereqs)
    ours_closure = Enum.reduce(ours, ours, &MapSet.union(&2, ctx.our_closure.(&1)))
    gates = our_gates(prereqs)

    base_missing =
      Enum.reject(base.and_rows, fn row ->
        row_satisfied?(ctx, row, ours_closure, gates)
      end)

    base_closure = ctx.feat_closure.(family)
    base_gates = base_gates(base)

    ours_extra =
      Enum.reject(ours, fn feat ->
        MapSet.member?(base_closure, feat) or
          implied_by_gates?(ctx, ctx.families[feat] || [], base_gates)
      end)

    Tally.check(
      tally,
      Enum.map(base_missing, &ctx.row_label.(&1)),
      Enum.map(ours_extra, &Atom.to_string/1),
      attrs.("feats", "PREREQFEAT1/2")
      |> Keyword.put(:same, fn a, b -> a == [] and b == [] end)
      |> Keyword.update(:base_at, "", &(&1 <> " — строки, которых не видно у нас"))
      |> Keyword.update(:ours_at, "", &(&1 <> ".feats — фиты, которых нет в .2da (с замыканием)"))
    )
  end

  defp or_feats(tally, ctx, family, base, prereqs, attrs) do
    ours_alternatives = prereqs["any_of"] || []

    feat_alternatives = Enum.filter(ours_alternatives, &Map.has_key?(&1, "feats"))

    cond do
      # Наш any_of из одних уровней классов — это ворота класса, а не «любой
      # из фитов»; в .2da то же выражают cls_feat_* (область feat_classes).
      base.or_rows == [] and feat_alternatives == [] ->
        tally

      base.or_rows != [] and Enum.all?(base.or_rows, &(ctx.feat_rows[&1] in @proficiencies)) ->
        Tally.check(
          tally,
          true,
          prereqs["proficiency_with_chosen_weapon"] == true,
          attrs.("proficiency", "OrReqFeat0–4 (фиты владения оружием)")
          |> Keyword.put(:ours_at, "feats.#{family}.prereqs.proficiency_with_chosen_weapon")
        )

      true ->
        base_unmatched =
          Enum.reject(base.or_rows, fn row ->
            Enum.any?(ours_alternatives, &alternative_matches?(ctx, &1, row))
          end)

        ours_unmatched =
          Enum.reject(ours_alternatives, fn alt ->
            Enum.any?(base.or_rows, &alternative_matches?(ctx, alt, &1))
          end)

        Tally.check(
          tally,
          Enum.map(base.or_rows, &ctx.row_label.(&1)),
          Enum.map(ours_alternatives, &show_alternative/1),
          attrs.("feats_or", "OrReqFeat0–4")
          |> Keyword.put(:same, fn _, _ -> base_unmatched == [] and ours_unmatched == [] end)
          |> Keyword.put(:ours_at, "feats.#{family}.prereqs.any_of")
        )
    end
  end

  # Наше требование характеристики может быть транзитивным: Improved Whirlwind
  # Attack у нас просит INT 13, а в .2da — Whirlwind Attack, который через
  # Expertise требует того же INT 13.
  defp abilities_agree?(ctx, family, base, ours) do
    implied =
      family
      |> ctx.feat_closure.()
      |> Enum.reduce(base, fn feat, acc ->
        {_row, req} = canonical(ctx, feat)
        Map.merge(acc, req.abilities, fn _k, a, b -> max(a, b) end)
      end)

    Enum.all?(base, fn {k, v} -> ours[k] == v end) and
      Enum.all?(ours, fn {k, v} -> Map.get(implied, k, 0) >= v end)
  end

  defp alternative_matches?(ctx, alt, row) do
    feats = MapSet.new(alt["feats"] || [], &String.to_existing_atom/1)
    gates = Map.new(alt["class_levels"] || %{}, fn {k, v} -> {String.to_existing_atom(k), v} end)

    (MapSet.size(feats) > 0 and row_satisfied?(ctx, row, feats, %{})) or
      (gates != %{} and implied_by_gates?(ctx, [row], gates))
  end

  defp show_alternative(alt) do
    alt
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join(" ")
  end

  defp class_gate(tally, family, base, prereqs, attrs) do
    case base.class_gate do
      nil ->
        tally

      {class, level} ->
        key = to_string(class)

        ours =
          get_in(prereqs, ["class_levels", key]) ||
            get_in(prereqs, ["qualifying_class_levels", key])

        Tally.check(
          tally,
          level,
          ours,
          attrs.("class_level/#{class}", "MinLevel + MinLevelClass")
          |> Keyword.put(
            :ours_at,
            "feats.#{family}.prereqs.class_levels / qualifying_class_levels"
          )
        )
    end
  end

  # ----------------------------------------------------------- repeatable --

  defp repeatable(ctx) do
    tally =
      Tally.new(:repeatable, "Фиты: повторяемость (цепочки ступеней и GAINMULTIPLE в feat.2da)")

    ctx.families
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(tally, fn {family, rows}, tally ->
      feat = ctx.ruleset.feats[family]
      chain = chain_length(ctx, family, rows)
      multiple = Enum.any?(rows, &(TwoDA.int(ctx.feat, &1, "GAINMULTIPLE") == 1))
      choice = choice_family?(ctx, family)
      repeatable = feat.repeatable

      # ⚠ Число, а не блок: `max_takes` в ruleset — карта с провенансом
      # (`%{value: 10, status: …}`), и сравнение карты с длиной цепочки
      # расходилось бы всегда — и при верном потолке тоже (задача 4.7: до неё
      # потолка у ванили не было ни одного, и промах не был виден).
      ours_takes = repeatable && get_in(repeatable, [Access.key(:max_takes), Access.key(:value)])

      cond do
        chain > 1 and granted_only?(ctx, family) ->
          Tally.check(tally, chain, ours_takes,
            subject: family,
            field: "max_takes",
            base_at: "feat.2da: ступеней в цепочке по PREREQFEAT — #{chain}",
            ours_at: "feats.#{family} — выдаётся классом ступенями (classes.*.granted_feats)",
            kind: :b,
            note:
              "Ступени выдаёт класс (cls_feat, List 3), игрок их не выбирает — потолок взятий тут не нужен."
          )

        chain > 1 ->
          Tally.check(tally, chain, ours_takes,
            subject: family,
            field: "max_takes",
            base_at: "feat.2da: ступеней в цепочке по PREREQFEAT — #{chain}",
            ours_at:
              "feats.#{family}.repeatable.max_takes" <>
                if(repeatable, do: "", else: " (repeatable = nil)")
          )

        multiple ->
          Tally.check(tally, true, not is_nil(repeatable),
            subject: family,
            field: "repeatable",
            base_at: "feat.2da: GAINMULTIPLE = 1",
            ours_at: "feats.#{family}.repeatable"
          )

        # Семейство выбора (задача 4.7): строка на каждое значение под общим
        # MASTERFEAT — фит берётся столько раз, сколько значений, каждое
        # однажды. У нас это блок повторяемости с доменом выбора; без него
        # выбор не записывается вовсе — `Epic skill focus` не прибавлял +10,
        # «with the chosen weapon» у `Epic weapon focus` не сравнивалось.
        choice and length(rows) > 1 ->
          Tally.check(tally, true, match?(%{choice: domain} when not is_nil(domain), repeatable),
            subject: family,
            field: "choice",
            base_at:
              "feat.2da: #{length(rows)} #{Report.plural(length(rows), "строка", "строки", "строк")} " <>
                "под MASTERFEAT — по фиту на значение",
            ours_at: "feats.#{family}.repeatable.choice"
          )

        not is_nil(repeatable) and not choice ->
          Tally.add(tally, "одна строка без GAINMULTIPLE", "повторяемый",
            subject: family,
            field: "repeatable",
            base_at: "feat.2da, строк: #{length(rows)}; ни цепочки, ни GAINMULTIPLE",
            ours_at: "feats.#{family}.repeatable"
          )

        true ->
          Tally.count(tally, 1)
      end
    end)
  end

  # Ступени связаны PREREQFEAT на предыдущую строку того же семейства; длина —
  # самая длинная такая цепочка (у Epic energy resistance их пять по десять).
  defp chain_length(ctx, family, rows) do
    self_prereq =
      Map.new(rows, fn row ->
        prev =
          for column <- ~w(PREREQFEAT1 PREREQFEAT2),
              r = TwoDA.int(ctx.feat, row, column),
              is_integer(r) and ctx.feat_rows[r] == family,
              do: r

        {row, List.first(prev)}
      end)

    rows
    |> Enum.map(&depth(&1, self_prereq, 1))
    |> Enum.max(fn -> 1 end)
  end

  defp depth(row, prev, n) do
    case prev[row] do
      nil -> n
      p when n < 64 -> depth(p, prev, n + 1)
      _ -> n
    end
  end

  # --------------------------------------------------------- availability --

  # ALLCLASSESCANUSE = 0: «доступность определяют таблицы cls_feat_*» (nwn.wiki).
  # Общим слотом на уровне класса C такой фит берётся, только если C его
  # перечисляет с List 0 или 1; List 2 — только бонусным слотом, List 3 —
  # выдача. У нас то же выражает `unavailable_feats` класса.
  defp availability(ctx) do
    tally =
      Tally.new(
        :feat_classes,
        "Фиты: на уровне какого класса берутся общим слотом (ALLCLASSESCANUSE и cls_feat List)"
      )

    classes = Map.keys(ctx.class_rows) |> Enum.sort()

    # Фит, который таблица не даёт выбрать нигде (MinLevel за капом, только
    # выдачи List 3), сверяется тоже — с пустым множеством: у нас его не должен
    # брать общий слот ни одного класса (задача 4.49 — Mount actions у Сиалы,
    # чью выдачу хак вынес за кап, брался общим и расовым слотом).
    families = ctx.families |> Map.keys() |> Enum.sort()

    Enum.reduce(families, tally, fn family, tally ->
      {_row, base} = canonical(ctx, family)
      feat = ctx.ruleset.feats[family]
      selectable? = selectable_somewhere?(ctx, family)

      # Наша сторона — ответ ЯДРА, а не его пересказ (задача 4.55): общий слот
      # на уровне класса спрашивается у `FeatSlots.accepts?/3` целиком — пул
      # общих фитов, выключенный фит, «не выбирается при левелапе», список
      # класса. До 4.55 здесь стояло своё прочтение (`type` вне
      # `granted_not_chosen/0`, плюс два флага, плюс `unavailable_feats`) — оно
      # совпадало с ядром, но не было им, а выбор фитов на экране держал третье,
      # более узкое, и сверка его не видела вовсе. Эпический общий слот — чтобы
      # не спрашивать «эпический ли фит»: колонка таблицы об этом молчит.
      general? = FeatSlots.general_feat?(ctx.ruleset, family)

      # Класс, которому фит выдаётся сам, в сравнение не входит: брать его
      # слотом незачем, и ни одна сторона об этом не спорит.
      open_by_base =
        for class <- classes,
            selectable?,
            not granted_to?(ctx, class, family),
            base.acu == 1 or lists?(ctx, class, family, [0, 1]),
            into: MapSet.new(),
            do: class

      open_by_ours =
        for class <- classes,
            not granted_to?(ctx, class, family),
            FeatSlots.accepts?(ctx.ruleset, general_slot(class), family),
            into: MapSet.new(),
            do: class

      Tally.check(tally, open_by_base, open_by_ours,
        subject: family,
        field: "general_slot_for",
        base_at:
          if(selectable?,
            do:
              "feat.2da ALLCLASSESCANUSE = #{base.acu}; cls_feat_*: List 0/1 (List 2 — только бонусный слот)",
            else:
              "feat.2da: не выбирается нигде — MinLevel #{inspect(base.min_level)}, ALLCLASSESCANUSE #{base.acu}, ни одной строки cls_feat_* с List 0/1/2 в пределах капа"
          ),
        ours_at:
          "FeatSlots: type «#{feat.type}» #{if general?, do: "в пуле", else: "не в пуле"} общих фитов; FeatSlots.accepts?/3 на уровне класса"
      )
    end)
  end

  # Эпический общий слот на уровне `class` — тот, что принимает и эпические,
  # и обычные фиты (`FeatSlots`: `:epic_general`).
  defp general_slot(class),
    do: %{id: :general, kind: :epic_general, class: nil, taken_with: class, epic?: true}

  # ---------------------------------------------------------------- parts --

  @doc false
  def canonical(ctx, family) do
    rows = ctx.families[family]
    base_rows = Enum.reject(rows, &self_prereq?(ctx, family, &1))
    base_rows = if base_rows == [], do: rows, else: base_rows

    row =
      if choice_family?(ctx, family) do
        base_rows
        |> Enum.group_by(&signature(row_req(ctx, family, &1)))
        |> Enum.max_by(fn {_sig, rs} -> {length(rs), -Enum.min(rs)} end)
        |> elem(1)
        |> Enum.min()
      else
        Enum.min(base_rows)
      end

    {row, row_req(ctx, family, row)}
  end

  defp signature(req), do: %{req | skills: req.skills |> Map.values() |> Enum.sort(), or_rows: []}

  @doc false
  def row_req(ctx, family, row) do
    t = ctx.feat
    int = &TwoDA.int(t, row, &1)

    prereq_rows = fn columns ->
      for column <- columns,
          r = int.(column),
          is_integer(r),
          ctx.feat_rows[r] != family,
          do: r
    end

    skills =
      for {skill_col, ranks_col} <- [
            {"REQSKILL", "ReqSkillMinRanks"},
            {"REQSKILL2", "ReqSkillMinRanks2"}
          ],
          s = int.(skill_col),
          is_integer(s),
          into: %{},
          do: {ctx.skill_rows[s], int.(ranks_col)}

    min_level = int.("MinLevel")
    min_class = int.("MinLevelClass")

    %{
      bab: int.("MINATTACKBONUS"),
      abilities:
        for({col, key} <- @abilities, n = int.(col), is_integer(n), into: %{}, do: {key, n}),
      spell_level: int.("MINSPELLLVL"),
      and_rows: prereq_rows.(~w(PREREQFEAT1 PREREQFEAT2)),
      or_rows: prereq_rows.(~w(OrReqFeat0 OrReqFeat1 OrReqFeat2 OrReqFeat3 OrReqFeat4)),
      skills: skills,
      class_gate:
        if(is_integer(min_class), do: {ctx.class_by_row[min_class] || min_class, min_level}),
      min_level: if(is_nil(min_class), do: min_level),
      max_level: int.("MaxLevel"),
      min_fort: int.("MinFortSave"),
      epic: int.("PreReqEpic") == 1,
      acu: int.("ALLCLASSESCANUSE")
    }
  end

  defp self_prereq?(ctx, family, row) do
    Enum.any?(~w(PREREQFEAT1 PREREQFEAT2), fn column ->
      r = TwoDA.int(ctx.feat, row, column)
      is_integer(r) and ctx.feat_rows[r] == family
    end)
  end

  @doc false
  def choice_family?(ctx, family) do
    Enum.any?(ctx.families[family], &(TwoDA.get(ctx.feat, &1, "MASTERFEAT") != nil))
  end

  defp our_feats(prereqs) do
    MapSet.new(
      (prereqs["feats"] || []) ++ (prereqs["same_choice_as"] || []),
      &String.to_existing_atom/1
    )
  end

  defp our_gates(prereqs) do
    [prereqs["class_levels"], prereqs["qualifying_class_levels"]]
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(%{}, &Map.merge/2)
    |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
  end

  defp base_gates(%{class_gate: {class, level}}) when is_atom(class), do: %{class => level || 1}
  defp base_gates(_base), do: %{}

  # Строка-требование засчитана: её семейство у нас есть и это первая ступень
  # (у семейства выбора — любая строка), либо её выдаёт наш уровень класса.
  defp row_satisfied?(ctx, row, our_feats, gates) do
    family = ctx.feat_rows[row]

    first_rank? =
      family != nil and (choice_family?(ctx, family) or row == Enum.min(ctx.families[family]))

    (first_rank? and MapSet.member?(our_feats, family)) or implied_by_gates?(ctx, [row], gates)
  end

  defp implied_by_gates?(_ctx, _rows, gates) when gates == %{}, do: false

  defp implied_by_gates?(ctx, rows, gates) do
    Enum.any?(rows, fn row ->
      Enum.any?(Map.get(ctx.grants, row, []), fn {class, level} ->
        case gates[class] do
          nil -> false
          have -> level <= have
        end
      end)
    end)
  end

  defp granted_only?(ctx, family) do
    not selectable_somewhere?(ctx, family)
  end

  # MinLevel 99 (DM Tool, Player Tool, подменю коня) — строка не выбирается
  # никогда, какой бы ни была ALLCLASSESCANUSE.
  defp selectable_somewhere?(ctx, family) do
    {_row, base} = canonical_cached(ctx, family)

    (base.min_level || 0) <= ctx.ruleset.level_cap and
      (base.acu == 1 or
         Enum.any?(ctx.class_lists, fn {_class, feats} ->
           Enum.any?(Map.get(feats, family, []), fn {list, level} ->
             list in [0, 1, 2] and level <= ctx.ruleset.level_cap
           end)
         end))
  end

  # Каноническая строка нужна и доступности, и требованиям; считать её дважды
  # дёшево, но ALLCLASSESCANUSE берётся ровно с той же строки.
  defp canonical_cached(ctx, family), do: canonical(ctx, family)

  defp granted_to?(ctx, class, family) do
    Enum.any?(Map.get(ctx.class_lists[class], family, []), &match?({3, _}, &1))
  end

  defp lists?(ctx, class, family, lists) do
    Enum.any?(Map.get(ctx.class_lists[class], family, []), fn {list, level} ->
      list in lists and level <= ctx.ruleset.level_cap
    end)
  end

  # Строки feat.2da без нашего id сводятся по виду: способности доменов,
  # маркеры «Epic <Class>», подменю верховой езды и всё прочее.
  defp unmapped_rows(tally, ctx) do
    ctx.unmapped_feat_rows
    |> Enum.group_by(fn {row, _name} ->
      Map.get(ctx.unmapped_groups, row) ||
        unmapped_group(TwoDA.get(ctx.feat, row, "LABEL") || "")
    end)
    |> Enum.sort()
    |> Enum.reduce(tally, fn {group, rows}, tally ->
      listed = Enum.map_join(rows, "; ", fn {row, name} -> "#{name} [#{row}]" end)

      Tally.add(tally, listed, nil,
        subject: group,
        field: "unmapped_rows",
        base_at: "feat.2da, строк без нашего id: #{length(rows)}",
        ours_at: "feats — нет id с таким именем"
      )
    end)
  end

  defp unmapped_group(label) do
    cond do
      String.ends_with?(label, "_Domain_Power") -> "domain_powers"
      String.starts_with?(label, "FEAT_EPIC_") -> "epic_class_markers"
      String.starts_with?(label, "HORSE_") -> "horse_menu"
      true -> "other"
    end
  end

  defp unmapped_ids(tally, ctx) do
    ctx.ruleset.feats
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(ctx.families, &1))
    |> Enum.sort()
    |> Enum.reduce(tally, fn id, tally ->
      Tally.add(tally, nil, ctx.ruleset.feats[id].name,
        subject: id,
        field: "unmapped_id",
        base_at: "feat.2da — строки с этим именем нет",
        ours_at: "feats.#{id}"
      )
    end)
  end
end
