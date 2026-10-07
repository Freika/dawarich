defmodule Dawarich.Geocoding.NightlyInvalidationWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 20

  @impl Oban.Worker
  def perform(%Oban.Job{args: payload, conf: conf}) do
    if conf.repo.in_transaction?() do
      {:error, :uncommitted_transaction}
    else
      Dawarich.Stats.CacheInvalidation.call(conf.repo, payload)
    end
  end
end
