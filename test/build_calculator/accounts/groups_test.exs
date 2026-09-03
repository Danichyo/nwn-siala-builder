defmodule BuildCalculator.Accounts.GroupsTest do
  use BuildCalculator.DataCase, async: true

  import BuildCalculator.AccountsFixtures
  import BuildCalculator.LibraryFixtures

  alias BuildCalculator.Accounts
  alias BuildCalculator.Library

  setup do
    owner = user_scope_fixture()
    stranger = user_scope_fixture()
    %{owner: owner, stranger: stranger}
  end

  describe "create_group/2" do
    test "makes the creator an owner", %{owner: owner} do
      assert {:ok, group} = Accounts.create_group(owner, %{name: "Гильдия"})
      assert group.name == "Гильдия"
      assert Accounts.group_role(owner, group) == :owner
    end

    test "mints an invite code the caller never supplied", %{owner: owner} do
      assert {:ok, group} = Accounts.create_group(owner, %{name: "A", invite_code: "guessable"})
      refute group.invite_code == "guessable"
      assert String.length(group.invite_code) == 12
    end

    test "requires a name", %{owner: owner} do
      assert {:error, changeset} = Accounts.create_group(owner, %{name: ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "fetch_group/2" do
    test "a member sees it, a stranger does not", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)

      assert {:ok, _} = Accounts.fetch_group(owner, group.id)
      assert {:error, :not_found} = Accounts.fetch_group(stranger, group.id)
    end

    test "a malformed id is not found, not a crash", %{owner: owner} do
      assert {:error, :not_found} = Accounts.fetch_group(owner, "nonsense")
    end
  end

  describe "join_group/2" do
    test "the invite code lets a stranger in", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)

      assert {:ok, joined} = Accounts.join_group(stranger, group.invite_code)
      assert joined.id == group.id
      assert Accounts.group_role(stranger, group) == :member
    end

    test "a wrong code says nothing about the group", %{stranger: stranger} do
      assert {:error, :invalid_code} = Accounts.join_group(stranger, "not-a-code")
    end

    test "joining twice is not an error", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)

      assert {:ok, _} = Accounts.join_group(stranger, group.invite_code)
      assert {:ok, _} = Accounts.join_group(stranger, group.invite_code)
      assert {:ok, members} = Accounts.list_group_members(owner, group)
      assert length(members) == 2
    end

    test "a rotated code invalidates the old one", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)
      old_code = group.invite_code

      assert {:ok, rotated} = Accounts.rotate_invite_code(owner, group)
      refute rotated.invite_code == old_code
      assert {:error, :invalid_code} = Accounts.join_group(stranger, old_code)
      assert {:ok, _} = Accounts.join_group(stranger, rotated.invite_code)
    end

    test "only an owner may rotate", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)

      assert {:error, :forbidden} = Accounts.rotate_invite_code(stranger, group)
    end

    # A minted code has 72 bits of entropy, so a collision cannot be provoked
    # through `rotate_invite_code/2` itself. What can be checked is that the
    # column really is unique and that the rotation's changeset is guarded: an
    # unguarded `Ecto.Changeset.change/2` reaches the index and *raises*
    # `Ecto.ConstraintError`, which no caller can pattern-match on and which
    # would make the `{:error, changeset}` branch of the caller dead code.
    test "a taken invite code is an error changeset, not a raised constraint", %{owner: owner} do
      taken = group_fixture(owner)
      other = group_fixture(owner)

      assert {:error, changeset} =
               other
               |> Ecto.Changeset.change(invite_code: taken.invite_code)
               |> Ecto.Changeset.unique_constraint(:invite_code)
               |> Repo.update()

      assert %{invite_code: ["has already been taken"]} = errors_on(changeset)

      assert_raise Ecto.ConstraintError, fn ->
        other
        |> Ecto.Changeset.change(invite_code: taken.invite_code)
        |> Repo.update()
      end
    end
  end

  describe "membership" do
    test "a member can leave", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)

      assert :ok = Accounts.leave_group(stranger, group)
      refute Accounts.group_member?(stranger, group)
    end

    test "the last owner may not leave", %{owner: owner} do
      group = group_fixture(owner)

      assert {:error, :last_owner} = Accounts.leave_group(owner, group)
      assert Accounts.group_role(owner, group) == :owner
    end

    test "an owner removes a member, a member cannot", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)
      third = user_scope_fixture()
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)
      {:ok, _} = Accounts.join_group(third, group.invite_code)

      assert {:error, :forbidden} = Accounts.remove_member(stranger, group, third.user)
      assert :ok = Accounts.remove_member(owner, group, third.user)
      refute Accounts.group_member?(third, group)
    end

    test "list_groups/1 returns only the caller's groups", %{owner: owner, stranger: stranger} do
      mine = group_fixture(owner)
      _theirs = group_fixture(stranger)

      assert Enum.map(Accounts.list_groups(owner), & &1.id) == [mine.id]
    end

    test "list_groups/1 отдаёт роль спросившего, и она у каждого своя", %{
      owner: owner,
      stranger: stranger
    } do
      group = group_fixture(owner, %{name: "Общая"})
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)

      assert [%{caller_role: :owner}] = Accounts.list_groups(owner)
      assert [%{caller_role: :member}] = Accounts.list_groups(stranger)
    end

    # Тот самый N+1: раньше экран групп добирал роль отдельным `group_role/2`
    # на каждую строку. Счёт запросов — единственное, что это доказывает:
    # по возвращаемому значению «одним запросом» от «пятью» не отличить.
    test "list_groups/1 — один запрос независимо от числа групп", %{owner: owner} do
      for n <- 1..5, do: group_fixture(owner, %{name: "Группа #{n}"})

      {groups, queries} = count_queries(fn -> Accounts.list_groups(owner) end)

      assert length(groups) == 5
      assert Enum.all?(groups, &(&1.caller_role == :owner))
      assert queries == 1
    end

    # ⚠️ Положительный контроль к предыдущему: если бы `caller_role` заполнялся
    # где угодно ещё, «один запрос» ничего бы не значило. Группа, взятая
    # не списком, роли не несёт и честно говорит об этом — `:not_loaded`,
    # а не `nil`, который читался бы как «не участник».
    test "группа не из списка не притворяется, что знает роль", %{owner: owner} do
      group = group_fixture(owner)

      assert {:ok, fetched} = Accounts.fetch_group(owner, group.id)
      assert fetched.caller_role == :not_loaded

      # А спросить роль по-прежнему можно — отдельным запросом, явно.
      assert Accounts.group_role(owner, fetched) == :owner
    end
  end

  # Считает запросы к базе, сделанные ИМЕННО этим процессом: обработчик
  # telemetry вызывается синхронно в процессе, который выполнил запрос,
  # поэтому соседние async-тесты в счёт не попадают.
  defp count_queries(fun) do
    test = self()
    ref = make_ref()
    handler = {__MODULE__, ref}

    :telemetry.attach(
      handler,
      [:build_calculator, :repo, :query],
      fn _event, _measure, _meta, _config ->
        if self() == test, do: send(test, {ref, :query})
      end,
      nil
    )

    try do
      {fun.(), drain(ref, 0)}
    after
      :telemetry.detach(handler)
    end
  end

  defp drain(ref, count) do
    receive do
      {^ref, :query} -> drain(ref, count + 1)
    after
      0 -> count
    end
  end

  describe "delete_group/2" do
    test "demotes the group's builds to private instead of deleting them", %{
      owner: owner,
      stranger: stranger
    } do
      group = group_fixture(owner)
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)

      shared =
        build_fixture(stranger, %{
          name: "Shared",
          visibility: :group,
          group_id: group.id
        })

      assert :ok = Accounts.delete_group(owner, group)

      # The build survives, and nobody but its owner can reach it any more.
      assert {:ok, kept} = Library.fetch_build(stranger, shared.id)
      assert kept.visibility == :private
      assert kept.group_id == nil
      assert {:error, :not_found} = Library.fetch_build(owner, shared.id)
    end

    test "only an owner may delete", %{owner: owner, stranger: stranger} do
      group = group_fixture(owner)
      {:ok, _} = Accounts.join_group(stranger, group.invite_code)

      assert {:error, :forbidden} = Accounts.delete_group(stranger, group)
    end
  end
end
