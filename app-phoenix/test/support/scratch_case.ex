defmodule Dawarich.ScratchCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Dawarich.ScratchRepo
      import Dawarich.ScratchCase, only: [scratch_sql!: 1]
    end
  end

  def scratch_sql!(sql) do
    Dawarich.ScratchRepo.query!(sql, [], query_type: :text, log: false)
    :ok
  end

  setup do
    Dawarich.ScratchRepo.query!("DROP SCHEMA IF EXISTS public CASCADE", [], log: false)
    Dawarich.ScratchRepo.query!("CREATE SCHEMA public", [], log: false)

    Dawarich.ScratchRepo.query!(
      "TRUNCATE phoenix.release_migration_jobs, phoenix.release_migrator_leases",
      [],
      log: false
    )

    :ok
  end
end
