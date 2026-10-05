defmodule Dawarich.Integrations.TeslaMateSchedulingWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 26
  alias Dawarich.Integrations.SyncScheduling

  def key, do: SyncScheduling.key(:teslamate)

  @impl Oban.Worker
  defdelegate backoff(job), to: SyncScheduling

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job),
    do: SyncScheduling.run(Dawarich.Jobs.repo(), conf.name, :teslamate, SyncScheduling.slot(job))
end
