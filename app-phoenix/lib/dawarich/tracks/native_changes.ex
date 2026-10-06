defmodule Dawarich.Tracks.NativeChanges do
  @moduledoc false

  require Logger
  alias Dawarich.{Cable, Redis}

  @columns ~w(id start_at end_at distance avg_speed duration elevation_gain elevation_loss elevation_max elevation_min original_path)

  def write!(repo, payload) do
    bump(payload)
    created = payload["created"]
    ids = created ++ payload["updated"]

    result =
      repo.query!(
        "SELECT id,start_at,end_at,COALESCE(distance,0),COALESCE(avg_speed,0),duration,elevation_gain," <>
          "elevation_loss,elevation_max,elevation_min,ST_AsText(original_path) FROM tracks WHERE user_id=$1 AND id=ANY($2) ORDER BY id",
        [payload["user_id"], ids],
        log: false
      )

    for values <- result.rows do
      track = @columns |> Enum.zip(values) |> Map.new()

      track =
        track
        |> Map.update!("start_at", &iso/1)
        |> Map.update!("end_at", &iso/1)
        |> Map.update!("original_path", &wkt/1)

      action = if track["id"] in created, do: "created", else: "updated"
      publish(repo, payload["user_id"], %{"action" => action, "track" => track})
    end

    for id <- payload["destroyed"],
        do: publish(repo, payload["user_id"], %{"action" => "destroyed", "track_id" => id})

    :ok
  end

  defp publish(repo, user, message) do
    case Cable.broadcast_to("tracks", {:user, user}, message, repo: repo) do
      :ok -> :ok
      {:error, _} -> Logger.warning("event=tracks.broadcast_failed user_id=#{user}")
    end
  end

  defp bump(payload) do
    from = year(payload["min_ts"])
    to = year(payload["max_ts"])
    years = if from <= to, do: Enum.to_list(from..to), else: ["all"]

    for year <- years do
      token = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      case Redis.cache_command(["SET", "tracks:tile_epoch:#{payload["user_id"]}:#{year}", token]) do
        {:ok, _} -> :ok
        {:error, _} -> Logger.warning("event=tracks.epoch_failed user_id=#{payload["user_id"]}")
      end
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
