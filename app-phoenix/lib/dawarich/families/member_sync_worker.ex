defmodule Dawarich.Families.MemberSyncWorker do
  @moduledoc false
  use Oban.Worker, queue: :families, max_attempts: 26
  alias Dawarich.Families.MemberSync
  alias Dawarich.Jobs.Processed

  def args_from_command(1, %{"family_id" => id, "locale" => locale, "time_zone" => zone} = p)
      when map_size(p) == 3 and is_integer(id) and
             id in -9_223_372_036_854_775_808..9_223_372_036_854_775_807 and is_binary(locale) and
             is_binary(zone),
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
        if Processed.claim!(repo, args["event_id"], "families.member_sync") do
          MemberSync.run(
            repo,
            args["family_id"],
            Keyword.merge(opts, locale: args["locale"], time_zone: args["time_zone"])
          )
        end

        :ok
      end)

    :ok
  end
end
