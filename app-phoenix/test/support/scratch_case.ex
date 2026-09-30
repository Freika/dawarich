defmodule Dawarich.ScratchCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Dawarich.ScratchCaseRepo

  using do
    quote do
      alias Dawarich.ScratchCaseRepo, as: ScratchRepo
      import Dawarich.ScratchCase, only: [scratch_sql!: 1]
    end
  end

  def scratch_sql!(sql) do
    ScratchCaseRepo.query!(sql, [], query_type: :text, log: false)
    :ok
  end

  def recreate_public!(repo) do
    repo.query!("DROP SCHEMA IF EXISTS public CASCADE", [], log: false)
    repo.query!("CREATE SCHEMA public", [], log: false)
    :ok = Supervisor.terminate_child(Dawarich.ScratchSupervisor, repo)
    {:ok, _} = Supervisor.restart_child(Dawarich.ScratchSupervisor, repo)
    :ok
  end

  setup do
    recreate_public!(ScratchCaseRepo)

    ScratchCaseRepo.query!(
      "TRUNCATE phoenix.release_migration_jobs, phoenix.release_migrator_leases",
      [],
      log: false
    )

    :ok
  end
end
