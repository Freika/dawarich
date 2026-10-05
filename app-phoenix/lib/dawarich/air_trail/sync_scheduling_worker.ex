defmodule Dawarich.AirTrail.SyncSchedulingWorker do
  @moduledoc false
  use Oban.Worker, queue: :imports, max_attempts: 3
  alias Dawarich.Integrations.SyncScheduling

  def key, do: SyncScheduling.key(:airtrail)
  defdelegate slot(job), to: SyncScheduling
  def event_id(slot, user_id), do: SyncScheduling.event_id(:airtrail, slot, user_id)
  def receipt_id(slot, user_id), do: SyncScheduling.receipt_id(:airtrail, slot, user_id)

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job), do: run(Dawarich.Jobs.repo(), conf.name, slot(job))

  def run(repo, oban, slot, opts \\ []), do: SyncScheduling.run(repo, oban, :airtrail, slot, opts)
end
