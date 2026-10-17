defmodule Dawarich.Tracks.RecentGeocoding do
  @moduledoc false

  alias Dawarich.Geocoding.{Config, NightlySweep, ReversePointWorker}
  alias Dawarich.Tracks.Owner
  alias Dawarich.{RailsCommands, State}

  def run(repo, oban, user_id, since, event \\ nil) do
    {:ok, :ok} =
      repo.transaction(fn ->
        if Owner.lock(repo, "command:geocoding.reverse_point") == :oban do
          if Config.resolve(repo).enabled,
            do: batch(repo, oban, user_id, since, event || Ecto.UUID.generate(), 0)
        else
          RailsCommands.insert!(repo, "geocode_recent_points", %{
            "user_id" => user_id,
            "since" => since
          })
        end

        :ok
      end)

    :ok
  end

  defp batch(repo, oban, user_id, since, event, cursor) do
    ids =
      repo.query!(
        "SELECT id FROM points WHERE user_id=$1 AND created_at > $2 AND reverse_geocoded_at IS NULL AND id > $3 ORDER BY id LIMIT 1000",
        [user_id, since |> DateTime.from_unix!() |> DateTime.to_naive(), cursor],
        log: false
      ).rows
      |> List.flatten()

    claimed = State.claim_persistent_all(repo, Enum.map(ids, &key/1)) |> MapSet.new()
    selected = Enum.filter(ids, &MapSet.member?(claimed, key(&1)))

    for chunk <- Enum.chunk_every(selected, 100) do
      args = %{
        "user_id" => user_id,
        "point_ids" => chunk,
        "force" => false,
        "cursor" => 0,
        "event_id" => NightlySweep.child_id(event, user_id, chunk)
      }

      Oban.insert!(oban, ReversePointWorker.new(args))
    end

    if length(ids) == 1000, do: batch(repo, oban, user_id, since, event, List.last(ids))
  end

  defp key(id), do: "geocode:enq:Point:#{id}"
end
