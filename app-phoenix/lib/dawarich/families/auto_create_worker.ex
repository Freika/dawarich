defmodule Dawarich.Families.AutoCreateWorker do
  @moduledoc false
  use Oban.Worker, queue: :families, max_attempts: 26
  alias Dawarich.Families.AutoCreate
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"user_id" => id, "time_zone" => zone} = p)
      when map_size(p) == 2 and is_integer(id) and
             id in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and is_binary(zone),
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

  def run(repo, args, opts \\ []) do
    {:ok, :ok} =
      repo.transaction(fn ->
        if Processed.claim!(repo, args["event_id"], "families.auto_create") do
          AutoCreate.run(repo, args["user_id"], Keyword.put(opts, :time_zone, args["time_zone"]))
        end

        :ok
      end)

    :ok
  end
end
