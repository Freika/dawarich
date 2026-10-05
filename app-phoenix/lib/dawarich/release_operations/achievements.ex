defmodule Dawarich.ReleaseOperations.Achievements do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.Achievements.{BulkCheck, BulkCheckWorker, Registry}
  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.RailsCommands
  alias Dawarich.ReleaseMigrations.Effects.LoadRegions
  alias Dawarich.ReleaseOperations

  defdelegate args_from_command(version, payload), to: ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1, "event_id" => _} = args, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args)

  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)

  def run(repo, oban, %{"version" => 1, "event_id" => event} = args, opts \\ []) do
    unless Processed.done?(repo, event) or not countries?(repo) do
      load_missing(repo)
      publish(repo, oban, args, opts)
    end

    :ok
  end

  defp load_missing(repo) do
    codes = Registry.subdivision_codes() |> MapSet.to_list()

    [[count]] =
      repo.query!("SELECT count(*) FROM regions WHERE code = ANY($1::varchar[])", [codes],
        log: false
      ).rows

    if count < length(codes) do
      unless countries?(repo),
        do: raise("countries table is empty: run db/seeds.rb before loading achievement regions")

      LoadRegions.run(repo)
    end
  end

  defp publish(repo, oban, args, opts) do
    {:ok, :ok} =
      repo.transaction(fn ->
        owner = Ownership.lock(repo, "command:achievements.bulk_check")

        if Processed.claim!(repo, args["event_id"], "release.achievements_backfill") do
          at = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
          job_id = BulkCheck.release_job_id(args["event_id"])
          options = %{"notify" => false, "force" => true, "stale_only" => true}

          case owner do
            :oban ->
              payload = Map.put(options, "event_id", BulkCheck.job_id(job_id))
              Oban.insert!(oban, BulkCheckWorker.new(payload, scheduled_at: at))

            :sidekiq ->
              RailsCommands.insert!(repo, "release_achievements_bulk_check", %{
                "job_id" => job_id,
                "options" => options,
                "run_at" => DateTime.to_iso8601(at)
              })
          end
        end

        :ok
      end)
  end

  defp countries?(repo),
    do: repo.query!("SELECT EXISTS (SELECT 1 FROM countries)", [], log: false).rows == [[true]]
end
