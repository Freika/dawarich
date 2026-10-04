defmodule Dawarich.Jobs.ImportEntries do
  @moduledoc false
  def entries do
    [
      %{
        key: "command:imports.immich_geodata",
        kind: :command,
        worker: Dawarich.Imports.Integrations.ImmichWorker,
        claimable: false
      },
      %{
        key: "command:imports.process_normal",
        kind: :command,
        worker: Dawarich.Imports.ProcessWorker,
        claimable: false
      }
    ]
  end
end
