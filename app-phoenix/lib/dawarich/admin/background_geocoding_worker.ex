defmodule Dawarich.Admin.BackgroundGeocodingWorker do
  @moduledoc false
  use Oban.Worker, queue: :reverse_geocoding, max_attempts: 4
  alias Dawarich.Geocoding.Config
  alias Dawarich.State

  @impl Oban.Worker
  def perform(%Oban.Job{id: id, args: args, conf: conf}) do
    repo = Dawarich.Jobs.repo()

    if Config.resolve(repo).enabled do
      repo.transaction(fn ->
        key = "admin:background_geocoding:#{id}"

        if State.claim_persistent_all(repo, [key]) == [key],
          do: batch(repo, conf.name, args),
          else: :ok
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp batch(repo, oban, args) do
    filter = if args["force"], do: "", else: " AND reverse_geocoded_at IS NULL"

    rows =
      repo.query!(
        "SELECT id FROM points WHERE user_id=$1 AND id>$2" <> filter <> " ORDER BY id LIMIT 1000",
        [args["user_id"], args["after_id"]],
        log: false
      ).rows

    ids = Enum.map(rows, &hd/1)
    keys = Enum.map(ids, &"geocode:enq:Point:#{&1}")

    selected =
      if args["force"] do
        State.unclaim_all(repo, keys)
        ids
      else
        claimed = State.claim_persistent_all(repo, keys) |> MapSet.new()
        Enum.filter(ids, &MapSet.member?(claimed, "geocode:enq:Point:#{&1}"))
      end

    for chunk <- Enum.chunk_every(selected, 100) do
      payload = %{"user_id" => args["user_id"], "point_ids" => chunk, "force" => args["force"]}

      repo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES(gen_random_uuid(),'geocoding.reverse_point',1,$1,$2,$3,now())",
        [payload, %{"producer" => "Jobs::Create", "locale" => args["locale"]}, args["user_id"]],
        log: false
      )
    end

    if length(ids) == 1000 do
      Oban.insert!(oban, new(Map.put(args, "after_id", List.last(ids))))
    end

    :ok
  end
end
