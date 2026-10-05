defmodule Dawarich.Places.DeleteIfOrphanWorker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, max_attempts: 26
  alias Dawarich.Jobs.Processed
  alias Dawarich.Places.Orphans

  def args_from_command(1, %{"user_id" => user, "place_id" => place} = p)
      when map_size(p) == 2 and is_integer(user) and
             user in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and is_integer(place) and
             place in -9_223_372_036_854_775_808..9_223_372_036_854_775_807,
      do: {:ok, p}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}), do: run(Dawarich.Jobs.repo(), args)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    count = attempt - 1
    Integer.pow(count, 4) + 15 + :rand.uniform(10 * (count + 1)) - 1
  end

  def run(repo, args) do
    {:ok, :ok} =
      repo.transaction(fn ->
        if Processed.claim!(repo, args["event_id"], "places.delete_if_orphan"),
          do: Orphans.delete(repo, args["user_id"], args["place_id"])

        :ok
      end)

    :ok
  end
end
