defmodule Dawarich.Users.PointsCounterCorrectionWorker do
  @moduledoc false

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Users

  @key "cron:points_counter_correction_job"
  @batch_size 1000

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{}), do: run(Dawarich.Jobs.repo(), @batch_size)

  def run(repo, batch_size), do: sweep(repo, 0, batch_size)

  defp sweep(repo, after_id, batch_size) do
    case Ownership.with_owner(repo, @key, :oban, fn ->
           Users.correct_points_counts(repo, after_id, batch_size)
         end) do
      {:ok, {:next, last_id}} -> sweep(repo, last_id, batch_size)
      {:ok, :done} -> :ok
      {:skip, _owner} -> {:cancel, :not_owner}
    end
  end
end
