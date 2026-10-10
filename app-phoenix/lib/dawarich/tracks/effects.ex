defmodule Dawarich.Tracks.Effects do
  @moduledoc false

  alias Dawarich.RailsCommands

  def write!(repo, user_id, changes) do
    created = Map.get(changes, :created, [])
    updated = Map.get(changes, :updated, [])
    destroyed = Map.get(changes, :destroyed, [])

    case Map.get(changes, :stamps, []) do
      [] ->
        :ok

      stamps ->
        payload = %{
          "user_id" => user_id,
          "created" => created,
          "updated" => updated,
          "destroyed" => destroyed,
          "min_ts" => stamps |> Enum.map(&epoch/1) |> Enum.min(),
          "max_ts" => stamps |> Enum.map(&epoch/1) |> Enum.max()
        }

        if Dawarich.Tracks.Owner.lock(repo, "command:tracks.generate_range") == :oban,
          do: Dawarich.Tracks.NativeChanges.write!(repo, payload),
          else: RailsCommands.insert!(repo, "tracks_changed", payload)
    end
  end

  defp epoch(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp epoch(%DateTime{} = at), do: DateTime.to_unix(at)
  defp epoch(at), do: at
end
