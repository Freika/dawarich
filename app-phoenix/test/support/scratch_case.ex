defmodule Dawarich.ScratchCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.ScratchCaseRepo

  using opts do
    if opts[:async] && opts[:group] != :scratch_case_db,
      do: raise(ArgumentError, "async ScratchCase modules need group: :scratch_case_db")

    quote do
      alias Dawarich.ScratchCaseRepo, as: ScratchRepo
      import Dawarich.ScratchCase, only: [scratch_sql!: 1]
      @moduletag scratch_fixture_tables: unquote(opts[:tables])
      @moduletag scratch_fixture_sequences: unquote(opts[:sequences] || [])
    end
  end

  def scratch_sql!(sql) do
    ScratchCaseRepo.query!(sql, [], query_type: :text, log: false)
    :ok
  end

  def recreate_public!(repo) do
    repo.query!("DROP SCHEMA IF EXISTS public CASCADE", [], log: false)
    repo.query!("CREATE SCHEMA public", [], log: false)

    supervisor =
      if repo == Dawarich.Repo, do: Dawarich.Supervisor, else: Dawarich.ScratchSupervisor

    :ok = Supervisor.terminate_child(supervisor, repo)
    {:ok, _} = Supervisor.restart_child(supervisor, repo)

    if repo == Dawarich.Repo, do: Ecto.Adapters.SQL.Sandbox.mode(repo, :auto)
    :ok
  end

  setup_all context do
    if context[:scratch_fixture_tables] do
      recreate_public!(ScratchCaseRepo)
      ExUnit.Callbacks.on_exit(fn -> recreate_public!(ScratchCaseRepo) end)
    end

    :ok
  end

  setup context do
    Dawarich.LaneGuard.guard!(:scratch_case_db)

    if tables = context[:scratch_fixture_tables] do
      Dawarich.FixtureCleanup.delete!(ScratchCaseRepo, tables)

      for table <- context.scratch_fixture_sequences do
        ScratchCaseRepo.query!("SELECT setval(pg_get_serial_sequence($1,'id'),1,false)", [table],
          log: false
        )
      end
    else
      recreate_public!(ScratchCaseRepo)
    end

    Dawarich.FixtureCleanup.delete!(
      ScratchCaseRepo,
      ~w(phoenix.release_migration_jobs phoenix.release_migrator_leases)
    )

    :ok
  end
end
