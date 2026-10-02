defmodule Dawarich.ReleaseOperations.PlacesUserId do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseMigrations.Effects.BackfillPlacesUserId

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1}}),
    do: BackfillPlacesUserId.run(Dawarich.Jobs.repo())

  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)
end
