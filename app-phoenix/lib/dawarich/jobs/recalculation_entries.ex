defmodule Dawarich.Jobs.RecalculationEntries do
  @moduledoc false

  def entries do
    [
      %{
        key: "command:users.recalculate_data",
        kind: :command,
        worker: Dawarich.Users.RecalculateWorker,
        claimable: false
      }
    ]
  end
end
