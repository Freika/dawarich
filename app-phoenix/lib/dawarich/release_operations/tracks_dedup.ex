defmodule Dawarich.ReleaseOperations.TracksDedup do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseMigrations.Effects.DedupeTracksForUniqueIndex
  alias Dawarich.ReleaseOperations

  def args_from_command(1, %{"user_id" => user_id} = payload)
      when map_size(payload) == 1 and is_integer(user_id),
      do: {:ok, %{"version" => 1, "user_id" => user_id}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version" => 1, "user_id" => user_id}}) when is_integer(user_id),
    do: run(Dawarich.Jobs.repo(), user_id)

  def perform(_job), do: {:cancel, :unsupported_version}

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(10)

  def run(repo, user_id) do
    if ReleaseOperations.user?(repo, user_id),
      do: DedupeTracksForUniqueIndex.dedupe_user(repo, user_id)

    :ok
  end
end
