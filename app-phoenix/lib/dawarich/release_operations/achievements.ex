defmodule Dawarich.ReleaseOperations.Achievements do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.Achievements.Registry
  alias Dawarich.ReleaseMigrations.Effects.LoadRegions
  alias Dawarich.ReleaseOperations

  defdelegate args_from_command(version, payload), to: ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1, "event_id" => _} = args, conf: conf}),
    do: run(Dawarich.Jobs.repo(), conf.name, args)

  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)

  def run(repo, _oban, %{"version" => 1}, _opts \\ []) do
    if countries?(repo) do
      codes = Registry.subdivision_codes() |> MapSet.to_list()

      [[count]] =
        repo.query!("SELECT count(*) FROM regions WHERE code = ANY($1::varchar[])", [codes],
          log: false
        ).rows

      if count < length(codes) do
        unless countries?(repo),
          do:
            raise("countries table is empty: run db/seeds.rb before loading achievement regions")

        LoadRegions.run(repo)
      end
    end

    :ok
  end

  defp countries?(repo),
    do: repo.query!("SELECT EXISTS (SELECT 1 FROM countries)", [], log: false).rows == [[true]]
end
