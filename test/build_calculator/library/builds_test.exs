defmodule BuildCalculator.Library.BuildsTest do
  use BuildCalculator.DataCase, async: true

  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Accounts
  alias BuildCalculator.Accounts.Scope
  alias BuildCalculator.Library

  setup do
    author = user_scope_fixture()
    stranger = user_scope_fixture()
    %{author: author, stranger: stranger, guest: guest_scope_fixture()}
  end

  describe "create_build/2" do
    test "stores the code and derives everything searchable from it", %{author: author} do
      code =
        build_code(
          race: :dwarf,
          levels: List.duplicate(:fighter, 10) ++ List.duplicate(:dwarven_defender, 23)
        )

      assert {:ok, build} =
               Library.create_build(author, %{name: "Гном Защитник", code: code})

      assert build.code == code
      assert build.user_id == author.user.id
      # Not taken from the form: read out of the code, so it cannot drift.
      assert build.ruleset_version == "siala_41"
      assert build.total_level == 33
      assert build.race == "dwarf"

      assert Enum.sort_by(build.class_levels, & &1.class_id)
             |> Enum.map(&{&1.class_id, &1.levels}) ==
               [{"dwarven_defender", 23}, {"fighter", 10}]
    end

    test "refuses a code that does not decode", %{author: author} do
      assert {:error, changeset} =
               Library.create_build(author, %{name: "Broken", code: "9.not-a-code"})

      assert %{code: ["is not a readable build code"]} = errors_on(changeset)
    end

    test "requires a name and a code", %{author: author} do
      assert {:error, changeset} = Library.create_build(author, %{})
      assert %{name: ["can't be blank"], code: ["can't be blank"]} = errors_on(changeset)
    end

    test "ignores a user_id in the params", %{author: author, stranger: stranger} do
      build = build_fixture(author, %{user_id: stranger.user.id})
      assert build.user_id == author.user.id
    end

    test "refuses group visibility for a group the author is not in", %{
      author: author,
      stranger: stranger
    } do
      group = group_fixture(stranger)

      assert {:error, changeset} =
               Library.create_build(author, %{
                 name: "Sneaky",
                 code: build_code(),
                 visibility: :group,
                 group_id: group.id
               })

      # Одно и то же сообщение на «нет такой группы» и «вы в ней не состоите»:
      # разные ответы дали бы перебор чужих id по реакции формы.
      assert %{group_id: ["Такой группы нет или вы в ней не состоите."]} = errors_on(changeset)
    end

    test "the same answer for a group that does not exist at all", %{author: author} do
      assert {:error, changeset} =
               Library.create_build(author, %{
                 name: "Sneaky",
                 code: build_code(),
                 visibility: :group,
                 group_id: Ecto.UUID.generate()
               })

      assert %{group_id: ["Такой группы нет или вы в ней не состоите."]} = errors_on(changeset)
    end

    test "refuses group visibility with no group at all", %{author: author} do
      assert {:error, changeset} =
               Library.create_build(author, %{
                 name: "Sneaky",
                 code: build_code(),
                 visibility: :group
               })

      # Другая ошибка, чем у чужой группы: тут человеку нечего исправлять
      # в списке — он просто не выбрал.
      assert %{group_id: ["Выберите группу: билд с видимостью «группа» должен её называть."]} =
               errors_on(changeset)
    end
  end

  describe "update_build/3" do
    test "recomputes the derived columns when the code changes", %{author: author} do
      build = build_fixture(author, %{code: build_code(race: :human, levels: [:wizard])})
      assert build.total_level == 1

      new_code = build_code(race: :elf, levels: List.duplicate(:rogue, 12))
      assert {:ok, updated} = Library.update_build(author, build, %{code: new_code})

      assert updated.total_level == 12
      assert updated.race == "elf"
      assert Enum.map(updated.class_levels, &{&1.class_id, &1.levels}) == [{"rogue", 12}]
    end

    test "a stranger cannot update somebody else's build", %{
      author: author,
      stranger: stranger
    } do
      build = build_fixture(author, %{name: "Mine"})

      assert {:error, :not_found} = Library.update_build(stranger, build, %{name: "Yours"})
      assert {:ok, unchanged} = Library.fetch_build(author, build.id)
      assert unchanged.name == "Mine"
    end

    test "clearing group visibility clears the group", %{author: author} do
      group = group_fixture(author)

      build =
        build_fixture(author, %{visibility: :group, group_id: group.id})

      assert build.group_id == group.id

      assert {:ok, updated} = Library.update_build(author, build, %{visibility: :private})
      assert updated.group_id == nil
    end
  end

  describe "delete_build/2" do
    test "the owner can, a stranger cannot", %{author: author, stranger: stranger} do
      build = build_fixture(author)

      assert {:error, :not_found} = Library.delete_build(stranger, build)
      assert {:ok, _} = Library.fetch_build(author, build.id)

      assert :ok = Library.delete_build(author, build)
      assert {:error, :not_found} = Library.fetch_build(author, build.id)
    end
  end

  describe "visibility" do
    test "public: everyone, including signed-out visitors", %{
      author: author,
      stranger: stranger,
      guest: guest
    } do
      build = build_fixture(author, %{visibility: :public})

      assert {:ok, _} = Library.fetch_build(author, build.id)
      assert {:ok, _} = Library.fetch_build(stranger, build.id)
      assert {:ok, _} = Library.fetch_build(guest, build.id)
    end

    test "private: the owner only", %{author: author, stranger: stranger, guest: guest} do
      build = build_fixture(author, %{visibility: :private})

      assert {:ok, _} = Library.fetch_build(author, build.id)
      assert {:error, :not_found} = Library.fetch_build(stranger, build.id)
      assert {:error, :not_found} = Library.fetch_build(guest, build.id)
    end

    test "group: members only, and only while they are members", %{
      author: author,
      stranger: stranger,
      guest: guest
    } do
      group = group_fixture(author)
      outsider = user_scope_fixture()
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)

      build = build_fixture(author, %{visibility: :group, group_id: group.id})

      assert {:ok, _} = Library.fetch_build(author, build.id)
      assert {:ok, _} = Library.fetch_build(stranger, build.id)
      assert {:error, :not_found} = Library.fetch_build(outsider, build.id)
      assert {:error, :not_found} = Library.fetch_build(guest, build.id)

      # Leaving the group takes the build away again.
      assert :ok = Accounts.leave_group(stranger, group)
      assert {:error, :not_found} = Library.fetch_build(stranger, build.id)
    end

    # ⚠️ Гость — это скоуп, а не его отсутствие. Пока `nil` и `%Scope{user: nil}`
    # значили одно и то же, каждый вызывающий решал сам, какое из двух проверять.
    # Тест закрепляет ровно одно написание: `nil` скоупом не является и падает
    # громко, а не превращается молча в «показать только публичное».
    test "у гостя одно написание, и nil в него не входит", %{author: author, guest: guest} do
      build = build_fixture(author, %{visibility: :public})

      assert Scope.for_user(nil) == %Scope{user: nil}

      # Положительный контроль: скоуп гостя работает и видит публичное.
      assert {:ok, _} = Library.fetch_build(guest, build.id)
      refute Library.can_edit?(guest, build)

      # `nil` через отсутствующий ключ, а не литералом: литерал ловит уже
      # проверка типов на компиляции (и ругается предупреждением), а из
      # рантайма скоуп приходит значением — вот этот путь и проверяется.
      assigns = %{flash: %{}}
      no_scope = assigns[:current_scope]

      assert_raise FunctionClauseError, fn -> Library.fetch_build(no_scope, build.id) end
      assert_raise FunctionClauseError, fn -> Library.can_edit?(no_scope, build) end
    end

    test "the public feed does not leak the caller's own private builds", %{author: author} do
      private = build_fixture(author, %{visibility: :private})
      public = build_fixture(author, %{visibility: :public})

      assert {:ok, page} = Library.list_public_builds(author)
      ids = Enum.map(page.entries, & &1.id)

      assert public.id in ids
      refute private.id in ids
    end

    test "a group feed is empty for outsiders", %{author: author, stranger: stranger} do
      group = group_fixture(author)
      _build = build_fixture(author, %{visibility: :group, group_id: group.id})

      assert {:ok, mine} = Library.list_group_builds(author, group)
      assert length(mine.entries) == 1

      assert {:ok, theirs} = Library.list_group_builds(stranger, group)
      assert theirs.entries == []
    end

    test "another author's profile shows only what the caller may see", %{
      author: author,
      stranger: stranger
    } do
      _private = build_fixture(author, %{visibility: :private})
      public = build_fixture(author, %{visibility: :public})

      assert {:ok, page} = Library.list_user_builds(stranger, author.user, [])
      assert Enum.map(page.entries, & &1.id) == [public.id]

      assert {:ok, own} = Library.list_user_builds(author, author.user, [])
      assert length(own.entries) == 2
    end
  end

  describe "can_edit?/2" do
    test "owner yes, everybody else no", %{author: author, stranger: stranger, guest: guest} do
      build = build_fixture(author)

      assert Library.can_edit?(author, build)
      assert Library.can_delete?(author, build)
      refute Library.can_edit?(stranger, build)
      refute Library.can_edit?(guest, build)
    end
  end

  describe "refresh_facts/1" do
    test "rebuilds the derived columns from the stored code", %{author: author} do
      build = build_fixture(author, %{code: build_code(race: :elf, levels: [:bard, :bard])})

      # Simulate a migration having dropped and re-added the search columns.
      Repo.update_all(from(b in Library.Build, where: b.id == type(^build.id, :binary_id)),
        set: [total_level: 0, race: nil]
      )

      Repo.delete_all(
        from c in Library.BuildClass, where: c.build_id == type(^build.id, :binary_id)
      )

      {:ok, stale} = Library.fetch_build(author, build.id)
      assert stale.total_level == 0

      assert {:ok, fixed} = Library.refresh_facts(stale)
      assert fixed.total_level == 2
      assert fixed.race == "elf"
      assert Enum.map(fixed.class_levels, &{&1.class_id, &1.levels}) == [{"bard", 2}]
    end
  end
end
