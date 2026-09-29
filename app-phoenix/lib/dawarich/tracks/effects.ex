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
        RailsCommands.insert!(repo, "tracks_changed", %{
          "user_id" => user_id,
          "created" => created,
          "updated" => updated,
          "destroyed" => destroyed,
          "min_ts" => Enum.min(stamps),
          "max_ts" => Enum.max(stamps)
        })
    end
  end
end
