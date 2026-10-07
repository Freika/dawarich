defmodule Dawarich.Tracks.NativeChanges do
  @moduledoc false

  alias Dawarich.{Cable, Redis}

  @columns ~w(id start_at end_at distance avg_speed duration elevation_gain elevation_loss elevation_max elevation_min original_path)

  def write!(repo, payload) do
    Dawarich.AfterCommit.cache(repo, "tracks", payload)
  end

  def deliver(repo, payload, intent) do
    if not Dawarich.Jobs.Processed.done?(repo, intent) do
      bump(payload, Ecto.UUID.generate())
    end

    Dawarich.AfterCommit.once(repo, intent, fn -> publish_changes(repo, payload) end)
  end

  def snapshot(_repo, %{"events" => _} = payload), do: payload

  def snapshot(repo, payload) do
    created = payload["created"]
    ids = created ++ payload["updated"]

    result =
      repo.query!(
        "SELECT id,start_at,end_at,COALESCE(distance,0),COALESCE(avg_speed,0),duration,elevation_gain," <>
          "elevation_loss,elevation_max,elevation_min,ST_AsText(original_path) FROM tracks WHERE user_id=$1 AND id=ANY($2) ORDER BY id",
        [payload["user_id"], ids],
        log: false
      )

    events =
      for values <- result.rows do
        track = @columns |> Enum.zip(values) |> Map.new()

        track =
          track
          |> Map.update!("start_at", &iso/1)
          |> Map.update!("end_at", &iso/1)
          |> Map.update!("original_path", &wkt/1)

        action = if track["id"] in created, do: "created", else: "updated"
        %{"action" => action, "track" => track}
      end

    destroyed = for id <- payload["destroyed"], do: %{"action" => "destroyed", "track_id" => id}
    Map.put(payload, "events", events ++ destroyed)
  end

  defp publish_changes(repo, payload) do
    events = Map.get_lazy(payload, "events", fn -> snapshot(repo, payload)["events"] end)
    for message <- events, do: publish(repo, payload["user_id"], message)
    :ok
  end

  defp publish(repo, user, message) do
    :ok = Cable.broadcast_to("tracks", {:user, user}, message, repo: repo)
  end

  defp bump(payload, token) do
    from = year(payload["min_ts"])
    to = year(payload["max_ts"])
    years = if from <= to, do: Enum.to_list(from..to), else: ["all"]

    for year <- years do
      {:ok, _} =
        Redis.cache_command(["SET", "tracks:tile_epoch:#{payload["user_id"]}:#{year}", token])
    end
  end

  defp wkt(nil), do: ""

  defp wkt(path),
    do: path |> String.replace_prefix("LINESTRING(", "LINESTRING (") |> String.replace(",", ", ")

  defp year(stamp),
    do: stamp |> DateTime.from_unix!() |> Map.fetch!(:year) |> max(1970) |> min(2100)

  defp iso(at),
    do:
      at
      |> DateTime.from_naive!("Etc/UTC")
      |> Map.put(:microsecond, {0, 0})
      |> DateTime.to_iso8601()
end
