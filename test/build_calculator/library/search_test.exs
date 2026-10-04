defmodule BuildCalculator.Library.SearchTest do
  use BuildCalculator.DataCase, async: true

  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Library

  setup do
    author = user_scope_fixture()
    %{author: author}
  end

  defp ids({:ok, page}), do: Enum.map(page.entries, & &1.id)

  describe "filter by class and level range" do
    setup %{author: author} do
      dip =
        build_fixture(author, %{
          name: "Rogue dip",
          visibility: :public,
          code: build_code(levels: List.duplicate(:fighter, 39) ++ List.duplicate(:rogue, 2))
        })

      thief =
        build_fixture(author, %{
          name: "Real thief",
          visibility: :public,
          code: build_code(levels: List.duplicate(:rogue, 30))
        })

      caster =
        build_fixture(author, %{
          name: "No rogue at all",
          visibility: :public,
          code: build_code(levels: List.duplicate(:wizard, 20))
        })

      %{dip: dip, thief: thief, caster: caster}
    end

    test "the class alone finds every build that has it", %{
      author: author,
      dip: dip,
      thief: thief,
      caster: caster
    } do
      found = ids(Library.list_public_builds(author, class: :rogue))

      assert dip.id in found
      assert thief.id in found
      refute caster.id in found
    end

    test "a range narrows to the builds actually invested in it", %{
      author: author,
      dip: dip,
      thief: thief
    } do
      deep = ids(Library.list_public_builds(author, class: :rogue, class_levels: 20..41))
      assert deep == [thief.id]

      shallow = ids(Library.list_public_builds(author, class: :rogue, class_levels: 1..5))
      assert shallow == [dip.id]
    end

    test "a range that matches nothing returns nothing", %{author: author} do
      assert ids(Library.list_public_builds(author, class: :rogue, class_levels: 31..41)) == []
    end

    test "the range boundaries are inclusive", %{author: author, thief: thief} do
      assert ids(Library.list_public_builds(author, class: :rogue, class_levels: 30..30)) ==
               [thief.id]
    end

    test "a build is never returned twice", %{author: author, thief: thief} do
      # Guards the EXISTS-over-join choice: a join would duplicate rows the
      # moment a build matched more than one class row, and duplicates silently
      # corrupt keyset paging.
      assert ids(Library.list_public_builds(author, class: :rogue, class_levels: 1..41))
             |> Enum.uniq() ==
               ids(Library.list_public_builds(author, class: :rogue, class_levels: 1..41))

      assert thief.id in ids(Library.list_public_builds(author, class: :rogue))
    end
  end

  describe "other filters" do
    test "by race", %{author: author} do
      dwarf = build_fixture(author, %{visibility: :public, code: build_code(race: :dwarf)})
      _elf = build_fixture(author, %{visibility: :public, code: build_code(race: :elf)})

      assert ids(Library.list_public_builds(author, race: :dwarf)) == [dwarf.id]
      assert ids(Library.list_public_builds(author, race: "dwarf")) == [dwarf.id]
    end

    test "by author", %{author: author} do
      other = user_scope_fixture()
      mine = build_fixture(author, %{visibility: :public})
      _theirs = build_fixture(other, %{visibility: :public})

      assert ids(Library.list_public_builds(author, author_id: author.user)) == [mine.id]
    end

    test "by name, case-insensitive substring", %{author: author} do
      target = build_fixture(author, %{name: "Мастер оружия Сагровик", visibility: :public})
      _other = build_fixture(author, %{name: "Бледный Призыватель", visibility: :public})

      assert ids(Library.list_public_builds(author, name: "сагровик")) == [target.id]
      assert ids(Library.list_public_builds(author, name: "оружия")) == [target.id]
      assert ids(Library.list_public_builds(author, name: "nothing here")) == []
    end

    test "LIKE wildcards in the search term are literal", %{author: author} do
      literal = build_fixture(author, %{name: "100% Fighter", visibility: :public})
      _decoy = build_fixture(author, %{name: "Something else", visibility: :public})

      assert ids(Library.list_public_builds(author, name: "100%")) == [literal.id]
      assert ids(Library.list_public_builds(author, name: "%")) == [literal.id]
    end

    test "by total level range", %{author: author} do
      short = build_fixture(author, %{visibility: :public, code: build_code(levels: [:bard])})

      long =
        build_fixture(author, %{
          visibility: :public,
          code: build_code(levels: List.duplicate(:bard, 41))
        })

      assert ids(Library.list_public_builds(author, total_level: 30..41)) == [long.id]
      assert ids(Library.list_public_builds(author, total_level: 1..5)) == [short.id]
    end

    test "filters compose", %{author: author} do
      match =
        build_fixture(author, %{
          name: "Dwarf Defender",
          visibility: :public,
          code: build_code(race: :dwarf, levels: List.duplicate(:dwarven_defender, 23))
        })

      _wrong_race =
        build_fixture(author, %{
          name: "Elf Defender",
          visibility: :public,
          code: build_code(race: :elf, levels: List.duplicate(:dwarven_defender, 23))
        })

      assert ids(
               Library.list_public_builds(author,
                 race: :dwarf,
                 class: :dwarven_defender,
                 class_levels: 20..41,
                 name: "defender"
               )
             ) == [match.id]
    end
  end

  describe "keyset pagination" do
    setup %{author: author} do
      now = DateTime.utc_now()

      # Two of the five share a timestamp on purpose: `updated_at` has
      # second precision, so ties are the normal case and the `id` tiebreaker
      # is what keeps the page boundary exact.
      builds =
        [-4, -3, -2, -2, -1]
        |> Enum.with_index(1)
        |> Enum.map(fn {offset, n} ->
          author
          |> build_fixture(%{name: "Build #{n}", visibility: :public})
          |> touch(DateTime.add(now, offset, :second))
        end)

      %{builds: builds}
    end

    test "walking the pages visits every build exactly once, in order", %{author: author} do
      {:ok, whole} = Library.list_public_builds(author, limit: 100)
      expected = Enum.map(whole.entries, & &1.id)
      assert length(expected) == 5

      assert walk(author, [], nil, limit: 2) == expected
    end

    test "an odd page size still ends cleanly", %{author: author} do
      {:ok, whole} = Library.list_public_builds(author, limit: 100)
      expected = Enum.map(whole.entries, & &1.id)

      assert walk(author, [], nil, limit: 3) == expected
      assert walk(author, [], nil, limit: 1) == expected
      assert walk(author, [], nil, limit: 5) == expected
    end

    test "the last page carries no cursor", %{author: author} do
      assert {:ok, page} = Library.list_public_builds(author, limit: 5)
      assert length(page.entries) == 5
      assert page.next_cursor == nil
      refute Library.Page.more?(page)
    end

    test "a full page that has more behind it does carry one", %{author: author} do
      assert {:ok, page} = Library.list_public_builds(author, limit: 4)
      assert length(page.entries) == 4
      assert Library.Page.more?(page)
    end

    test "filters survive across the page boundary", %{author: author} do
      # Same filter on every page: paging must not widen what is visible.
      ids = walk(author, [], nil, limit: 2, class: :fighter)
      assert length(ids) == 5

      assert walk(author, [], nil, limit: 2, class: :rogue) == []
    end

    test "a mangled cursor is reported, not silently ignored", %{author: author} do
      assert {:error, :bad_cursor} = Library.list_public_builds(author, cursor: "!!!!")
      assert {:error, :bad_cursor} = Library.list_public_builds(author, cursor: 42)
    end

    test "the page size is capped", %{author: author} do
      assert {:ok, _} = Library.list_public_builds(author, limit: 10_000)
      assert {:ok, page} = Library.list_public_builds(author, limit: 0)
      assert length(page.entries) == 5
    end
  end

  describe "paging backwards" do
    setup %{author: author} do
      now = DateTime.utc_now()

      builds =
        for n <- 1..5 do
          author
          |> build_fixture(%{name: "Build #{n}", visibility: :public})
          |> touch(DateTime.add(now, -n, :second))
        end

      %{builds: builds}
    end

    test "the first page has nothing above it", %{author: author} do
      assert {:ok, page} = Library.list_public_builds(author, limit: 2)
      assert page.previous_cursor == nil
      refute Library.Page.previous?(page)
      assert Library.Page.more?(page)
    end

    test "going back lands on exactly the page we came from", %{author: author} do
      # ⚠️ Главная проверка всей правки. Оба сравнения курсора строгие, поэтому
      # шаг назад «от курсора» вместо «от первой строки экрана» промахивался бы
      # ровно на одну запись — и она пропадала бы на КАЖДОЙ границе страниц,
      # молча и одинаково незаметно во всех лентах.
      assert {:ok, first} = Library.list_public_builds(author, limit: 2)

      assert {:ok, second} =
               Library.list_public_builds(author, limit: 2, cursor: first.next_cursor)

      assert {:ok, back} =
               Library.list_public_builds(author, limit: 2, cursor: second.previous_cursor)

      assert ids({:ok, back}) == ids({:ok, first})
    end

    test "the last page has a way up but not down", %{author: author} do
      assert {:ok, last} = walk_to_last(author, limit: 2)

      assert last.next_cursor == nil
      assert last.previous_cursor != nil

      # 5 записей по 2 — последняя страница неполная, и это не мешает вернуться.
      assert length(last.entries) == 1
    end

    test "walking down and back up visits the same builds in the same order", %{author: author} do
      {:ok, whole} = Library.list_public_builds(author, limit: 100)
      expected = Enum.map(whole.entries, & &1.id)

      down = pages_down(author, limit: 2)
      assert List.flatten(down) == expected

      # Обратный проход обязан вернуть те же страницы, а не «те же записи»:
      # съехавшая на строку граница дала бы тот же набор id и прошла бы
      # проверку по множеству.
      up = pages_up(author, limit: 2)
      assert up == down
    end

    test "one page only: neither arrow", %{author: author} do
      assert {:ok, page} = Library.list_public_builds(author, limit: 100)
      refute Library.Page.more?(page)
      refute Library.Page.previous?(page)
    end

    test "a page exactly the size of the limit still ends the feed", %{author: author} do
      # Классическая ловушка «n+1»: страница ровно по лимиту выглядит полной,
      # но следующей за ней нет — стрелка «дальше» вела бы в пустоту.
      assert {:ok, page} = Library.list_public_builds(author, limit: 5)
      assert length(page.entries) == 5
      assert page.next_cursor == nil
      assert page.previous_cursor == nil
    end

    test "a full last page reached by cursor has no way down", %{author: author} do
      # 5 записей по лимиту 4: вторая страница неполная. Берём лимит 5 на второй
      # шаг, чтобы граница пришлась ровно на конец ленты.
      assert {:ok, first} = Library.list_public_builds(author, limit: 3)

      assert {:ok, second} =
               Library.list_public_builds(author, limit: 2, cursor: first.next_cursor)

      assert length(second.entries) == 2
      assert second.next_cursor == nil
      assert second.previous_cursor != nil
    end

    test "builds sharing one updated_at page both ways without loss", %{author: author} do
      # `updated_at` секундной точности: одинаковый ключ сортировки — норма,
      # а не редкость. Уникален только `id`, и на нём одном держится граница.
      same = DateTime.utc_now() |> DateTime.add(-1, :hour)

      for n <- 1..7 do
        author
        |> build_fixture(%{name: "Одновременно #{n}", visibility: :public})
        |> touch(same)
      end

      {:ok, whole} = Library.list_public_builds(author, limit: 100)
      expected = Enum.map(whole.entries, & &1.id)
      assert length(expected) == 12
      assert Enum.uniq(expected) == expected

      down = pages_down(author, limit: 3)
      assert List.flatten(down) == expected
      assert pages_up(author, limit: 3) == down
    end

    test "a backwards cursor keeps the filter it was taken from", %{author: author} do
      # Курсор и фильтр — одно состояние. Если фильтр по дороге теряется,
      # «назад» показывает чужую ленту, и это заметно не сразу.
      _decoy = build_fixture(author, %{name: "Мимо фильтра", visibility: :public})

      filtered = [limit: 2, name: "Build"]

      {:ok, first} = Library.list_public_builds(author, filtered)

      {:ok, second} =
        Library.list_public_builds(author, Keyword.put(filtered, :cursor, first.next_cursor))

      {:ok, back} =
        Library.list_public_builds(author, Keyword.put(filtered, :cursor, second.previous_cursor))

      assert ids({:ok, back}) == ids({:ok, first})
      assert pages_down(author, filtered) |> List.flatten() |> length() == 5
    end

    test "a cursor without a direction is refused", %{author: author} do
      # Старый формат курсора (`unix:id`, без стороны) читается ровно как мусор:
      # угадывать направление — значит однажды угадать не туда.
      stale = Base.url_encode64("1750000000:#{Ecto.UUID.generate()}", padding: false)

      assert {:error, :bad_cursor} = Library.list_public_builds(author, cursor: stale)
    end
  end

  defp walk(scope, acc, cursor, opts) do
    {:ok, page} = Library.list_public_builds(scope, Keyword.put(opts, :cursor, cursor))
    acc = acc ++ Enum.map(page.entries, & &1.id)

    case page.next_cursor do
      nil -> acc
      next -> walk(scope, acc, next, opts)
    end
  end

  # Каждая страница отдельным списком id — так видно не только «все записи
  # на месте», но и что границы стоят там же.
  defp pages_down(scope, opts, cursor \\ nil, acc \\ []) do
    {:ok, page} = Library.list_public_builds(scope, Keyword.put(opts, :cursor, cursor))
    acc = acc ++ [Enum.map(page.entries, & &1.id)]

    case page.next_cursor do
      nil -> acc
      next -> pages_down(scope, opts, next, acc)
    end
  end

  defp pages_up(scope, opts) do
    {:ok, last} = walk_to_last(scope, opts)
    up(scope, opts, last, [Enum.map(last.entries, & &1.id)])
  end

  defp up(_scope, _opts, %{previous_cursor: nil}, acc), do: acc

  defp up(scope, opts, page, acc) do
    {:ok, previous} =
      Library.list_public_builds(scope, Keyword.put(opts, :cursor, page.previous_cursor))

    up(scope, opts, previous, [Enum.map(previous.entries, & &1.id) | acc])
  end

  defp walk_to_last(scope, opts, cursor \\ nil) do
    {:ok, page} = Library.list_public_builds(scope, Keyword.put(opts, :cursor, cursor))

    case page.next_cursor do
      nil -> {:ok, page}
      next -> walk_to_last(scope, opts, next)
    end
  end
end
