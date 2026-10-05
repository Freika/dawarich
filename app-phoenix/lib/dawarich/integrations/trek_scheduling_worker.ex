defmodule Dawarich.Integrations.TrekSchedulingWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 3
  alias Dawarich.Integrations.SyncScheduling

  def key, do: SyncScheduling.key(:trek)

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job),
    do: SyncScheduling.run(Dawarich.Jobs.repo(), conf.name, :trek, SyncScheduling.slot(job))
end
