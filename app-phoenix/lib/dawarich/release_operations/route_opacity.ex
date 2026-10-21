defmodule Dawarich.ReleaseOperations.RouteOpacity do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  @sql """
  UPDATE users
  SET settings = jsonb_set(settings, '{route_opacity}', to_jsonb((settings->>'route_opacity')::float / 100.0))
  WHERE deleted_at IS NULL AND (settings->>'route_opacity')::float > 1
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
