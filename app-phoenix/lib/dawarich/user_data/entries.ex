defmodule Dawarich.UserData.Entries do
  @moduledoc false
  def entries,
    do: [
      %{
        key: "command:users.export_data",
        kind: :command,
        worker: Dawarich.UserData.ExportWorker,
        claimable: false
      }
    ]
end
