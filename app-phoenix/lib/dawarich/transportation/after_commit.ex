defmodule Dawarich.Transportation.AfterCommit do
  @moduledoc false
  alias Dawarich.Transportation.{RecalculationFence, RecalculationStatus}

  def start(repo, payload, intent) do
    user = payload["user_id"]
    {:ok, now, _} = DateTime.from_iso8601(payload["now"])
    ids = payload["track_ids"]
    RecalculationStatus.start(user, length(ids), now)

    Dawarich.AfterCommit.once(repo, intent, fn ->
      ids
      |> Enum.chunk_every(100)
      |> Enum.with_index()
      |> Enum.each(fn {slice, index} ->
        Enum.each(slice, fn id ->
          args = %{"track_id" => id, "report_progress" => true, "user_id" => user}

          metadata = %{
            "producer" => "Phoenix UserReclassify",
            "parent_event_id" => payload["event_id"],
            "locale" => payload["locale"],
            "time_zone" => payload["time_zone"]
          }

          repo.query!(
            "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at) VALUES($1,'transportation.reclassify_track',1,$2,$3,$4,$5)",
            [Ecto.UUID.bingenerate(), args, metadata, id, DateTime.add(now, index * 10)],
            log: false
          )
        end)
      end)

      RecalculationFence.start(repo, user, payload["event_id"], length(ids))
      :ok
    end)
  rescue
    error ->
      {:ok, now, _} = DateTime.from_iso8601(payload["now"])
      RecalculationStatus.fail(payload["user_id"], now, Exception.message(error))
      reraise error, __STACKTRACE__
  end

  def progress(repo, payload, intent) do
    user = payload["user_id"]
    RecalculationStatus.increment(user, payload["event_id"])
    status = RecalculationStatus.data(user)

    Dawarich.AfterCommit.once(repo, intent, fn ->
      RecalculationFence.progress(repo, user, payload["event_id"])

      :ok =
        Dawarich.Cable.broadcast_to(
          "tracks",
          {:user, user},
          %{
            "action" => "transport_progress",
            "status" => status
          },
          repo: repo
        )

      :ok
    end)
  end
end
