defmodule Dawarich.Geocoding.NightlyWorker do
  @moduledoc false
  use Oban.Worker, queue: :reverse_geocoding, max_attempts: 26

  alias Dawarich.Geocoding.NightlySweep

  def key, do: "cron:nightly_reverse_geocoding_job"

  @impl Oban.Worker
  def new(%{"slot" => _} = args, opts),
    do:
      super(
        args,
        Keyword.put(opts, :unique, keys: [:slot, :after_id], states: :all, period: :infinity)
      )

  def new(args, opts), do: super(args, opts)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"slot" => _} = args, conf: conf}),
    do: NightlySweep.run(Dawarich.Jobs.repo(), conf.name, args)

  def perform(%Oban.Job{conf: conf} = job),
    do: run(Dawarich.Jobs.repo(), conf.name, Dawarich.Integrations.SyncScheduling.slot(job))

  def run(repo, oban, slot, opts \\ []),
    do:
      NightlySweep.run(
        repo,
        oban,
        %{"slot" => slot, "after_id" => 0, "affected_user_ids" => []},
        opts
      )

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)
end
