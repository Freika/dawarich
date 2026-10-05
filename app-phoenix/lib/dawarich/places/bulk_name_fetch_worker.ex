defmodule Dawarich.Places.BulkNameFetchWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :places,
    max_attempts: 26,
    unique: [keys: [:event_id, :cursor], period: :infinity, states: :all]

  alias Dawarich.Jobs.{Ownership, Processed}
  alias Dawarich.Places.NameFetchWorker

  def args_from_command(1, p) when is_map(p) and map_size(p) == 0,
    do: {:ok, %{"cursor" => 0}}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}

  def batch_id(args), do: identity(args["event_id"], "batch:#{args["cursor"]}")

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, conf: conf}), do: run(Dawarich.Jobs.repo(), conf.name, args)

  @impl Oban.Worker
  def backoff(job), do: Dawarich.Integrations.SyncScheduling.backoff(job)

  def run(repo, oban, args, opts \\ []) do
    {:ok, :ok} =
      repo.transaction(fn ->
        owner =
          if args["cursor"] == 0,
            do: :oban,
            else: Ownership.lock(repo, "command:places.bulk_name_fetch")

        leaf = Ownership.lock(repo, "command:places.name_fetch")

        if Processed.claim!(repo, batch_id(args), "places.bulk_name_fetch") do
          if owner == :oban do
            publish(repo, oban, args, leaf, opts)
          else
            Dawarich.RailsCommands.insert!(repo, "places_bulk_name_fetch", %{})
          end
        end

        :ok
      end)

    :ok
  end

  defp publish(repo, oban, args, owner, opts) do
    rows =
      repo.query!(
        "SELECT id,user_id FROM places WHERE id>$1 AND name='Suggested place' ORDER BY id LIMIT 1000",
        [args["cursor"]],
        log: false
      ).rows

    Enum.each(rows, fn [id, user] ->
      payload = %{"user_id" => user, "place_id" => id}

      if owner == :oban do
        event = identity(args["event_id"], "place:#{id}")
        Oban.insert!(oban, NameFetchWorker.new(Map.put(payload, "event_id", event)))
      else
        Dawarich.RailsCommands.insert!(repo, "place_name_fetch", payload)
      end

      Keyword.get(opts, :hook, fn _ -> :ok end).(id)
    end)

    if length(rows) == 1000 do
      Oban.insert!(oban, new(Map.put(args, "cursor", rows |> List.last() |> hd())))
    end

    :ok
  end

  defp identity(root, name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha, Ecto.UUID.dump!(root) <> name)

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
