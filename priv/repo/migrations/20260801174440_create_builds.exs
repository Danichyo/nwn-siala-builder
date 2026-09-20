defmodule BuildCalculator.Repo.Migrations.CreateBuilds do
  use Ecto.Migration

  def change do
    # `name ILIKE '%...%'` is a substring match, which no b-tree can serve.
    # A trigram GIN index can, and the alternative — restricting the UI to
    # prefix search — is a worse product for the sake of a cheaper index.
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", ""

    create table(:builds, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :description, :text

      # The source of truth. Every other game column below is derived from this
      # one and can be rebuilt by a migration; this one never migrates, because
      # the codec versions itself (BuildCalculator.Encoding).
      add :code, :text, null: false

      # A build is always recomputed with the ruleset it was built in
      # (CLAUDE.md §5), so this is not optional and not "whatever is newest".
      add :ruleset_version, :string, null: false

      add :visibility, :string, null: false, default: "private"
      # `:nothing` on purpose: nilifying would leave a row that fails the check
      # below, and cascading would silently delete other people's builds.
      # `Library.delete_group/2` makes group builds private first.
      add :group_id, references(:groups, type: :binary_id, on_delete: :nothing)

      # ---- denormalised from `code`, for search and list rendering only ----
      add :total_level, :integer, null: false, default: 0
      add :race, :string

      timestamps(type: :utc_datetime)
    end

    # The one invariant the context must never be able to break: a "group" build
    # without a group is visible to nobody, and a group on a public build is a
    # leak waiting for the next `where` clause to be written wrong.
    create constraint(:builds, :builds_group_visibility,
             check: "(visibility = 'group') = (group_id IS NOT NULL)"
           )

    # Every feed is `ORDER BY updated_at DESC, id DESC` with a keyset cursor.
    # The index columns are left ascending on purpose: the ordering is reversed
    # uniformly, so Postgres reads these backwards and the cursor comparison
    # `(updated_at, id) < (?, ?)` becomes a plain index seek.

    # "my builds" / "builds by this author"
    create index(:builds, [:user_id, :updated_at, :id])

    # the public feed — partial, because that is the only visibility it serves
    create index(:builds, [:updated_at, :id],
             where: "visibility = 'public'",
             name: :builds_public_feed_index
           )

    # one group's feed (and the FK index)
    create index(:builds, [:group_id, :updated_at, :id])

    # filter by race, still in feed order
    create index(:builds, [:race, :updated_at, :id])

    # filter by total level — a range on the leading column, so the ordering
    # cannot come from the index too; a plain b-tree is the honest shape here
    create index(:builds, [:total_level])

    # `name ILIKE '%...%'`
    execute(
      "CREATE INDEX builds_name_trgm_index ON builds USING gin (name gin_trgm_ops)",
      "DROP INDEX builds_name_trgm_index"
    )

    # Class composition, denormalised out of `code`. A row per class rather than
    # a JSON column, because the query the wiki trained people to run is
    # "class X, between N and M levels" — a range, which a b-tree serves and a
    # JSON containment index does not.
    create table(:build_classes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :build_id, references(:builds, type: :binary_id, on_delete: :delete_all), null: false
      add :class_id, :string, null: false
      add :levels, :integer, null: false
    end

    # One row per class per build; also the path used to preload a listed
    # build's composition.
    create unique_index(:build_classes, [:build_id, :class_id])

    # "class X between N and M levels" — `build_id` rides along so the lookup
    # never has to touch the table heap.
    create index(:build_classes, [:class_id, :levels, :build_id])
  end
end
