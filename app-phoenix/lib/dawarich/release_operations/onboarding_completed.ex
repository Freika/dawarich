defmodule Dawarich.ReleaseOperations.OnboardingCompleted do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  @sql """
  UPDATE users
  SET settings = jsonb_set(COALESCE(settings, '{}'), '{onboarding_completed}', 'true')
  WHERE deleted_at IS NULL AND points_count > 0 AND (settings->>'onboarding_completed') IS NULL
  """

  defdelegate args_from_command(version, payload), to: Dawarich.ReleaseOperations, as: :no_payload

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1}}), do: run(Dawarich.Jobs.repo())
  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo) do
    repo.query!(@sql, [], log: false)
    :ok
  end
end
