defmodule Dawarich.Imports.WatcherWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :imports,
    max_attempts: 1,
    unique: [states: :incomplete, period: :infinity]

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: Dawarich.Imports.Watcher.run(Dawarich.Jobs.repo())
end
