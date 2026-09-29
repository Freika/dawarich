defmodule Dawarich.ReleaseMigrator.BaselineTest.PostFloor do
  @behaviour Dawarich.ReleaseMigration

  alias Dawarich.RailsTree
  alias Dawarich.ReleaseMigrator.Floor

  @impl true
  def release, do: "post-floor"

  @impl true
  def steps do
    floor = MapSet.new(Floor.versions())

    for version <- RailsTree.versions("migrate"), not MapSet.member?(floor, version) do
      if RailsTree.disables_ddl_transaction?(version) do
        {version, fn _repo -> :ok end, transaction: false}
      else
        {version, fn _repo -> :ok end}
      end
    end
  end

  @impl true
  def data_versions, do: []
end

defmodule Dawarich.ReleaseMigrator.BaselineTest do
  use Dawarich.ScratchCase

  import Dawarich.ReleaseMigration

  alias Dawarich.{RailsTree, ReleaseMigrator}
  alias Dawarich.ReleaseMigrator.BaselineTest.PostFloor

  @rails_ledger_tables """
  CREATE TABLE "schema_migrations" ("version" character varying NOT NULL PRIMARY KEY);
  CREATE TABLE "ar_internal_metadata" ("key" character varying NOT NULL PRIMARY KEY, "value" character varying, "created_at" timestamp(6) NOT NULL, "updated_at" timestamp(6) NOT NULL);
  """

  test "the shipped baseline builds the Rails schema and records every migration up to its newest" do
    assert {:ok, :ok} =
             ScratchRepo.transaction(
               fn -> sql!(ScratchRepo, ReleaseMigrator.baseline_sql()) end,
               timeout: :infinity
             )

    for table <- ~w[users points tracks schema_migrations ar_internal_metadata data_migrations] do
      assert table?(ScratchRepo, table), table
    end

    %{rows: rows} = ScratchRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    ledger = List.flatten(rows)
    assert ledger != []
    assert ledger == Enum.filter(RailsTree.versions("migrate"), &(&1 <= List.last(ledger)))
  end

  test "an empty ledger in an otherwise empty public takes the baseline" do
    scratch_sql!(@rails_ledger_tables)

    assert {:ok, %{applied: ["baseline" | _]}} =
             ReleaseMigrator.migrate(ScratchRepo, releases: [PostFloor])

    assert table?(ScratchRepo, "users")
  end

  test "an empty ledger beside an application table stops the baseline there and changes nothing" do
    scratch_sql!(@rails_ledger_tables <> "CREATE TABLE users (id bigserial primary key);")

    assert {:error, {:failed, "baseline", nil, message}} = ReleaseMigrator.migrate(ScratchRepo)
    assert message =~ ~s|relation "users" already exists|
    refute table?(ScratchRepo, "points")
    assert %{rows: []} = ScratchRepo.query!("SELECT version FROM schema_migrations")
  end

  test "a fresh database reaches every Rails migration through the baseline and the release modules" do
    assert {:ok, %{applied: ["baseline" | _]}} = ReleaseMigrator.migrate(ScratchRepo)
    %{rows: rows} = ScratchRepo.query!("SELECT version FROM schema_migrations ORDER BY version")
    assert List.flatten(rows) == RailsTree.versions("migrate")
  end
end
