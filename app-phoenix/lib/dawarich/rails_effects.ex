defmodule Dawarich.RailsEffects do
  @moduledoc false

  alias Dawarich.RailsCommands

  def tile_epoch(repo, user_id, timestamps) do
    payload = %{"user_id" => user_id, "timestamps" => timestamps}

    if Dawarich.Points.NativeEffects.native?(repo, "command:points.tile_epoch"),
      do: Dawarich.Points.NativeEffects.enqueue(repo, Dawarich.Points.TileEpochWorker, payload),
      else: RailsCommands.insert!(repo, "points.tile_epoch", payload)
  end

  def untracked_tracks(repo, user_id, import_id),
    do:
      RailsCommands.insert!(repo, "schedule_untracked_tracks", %{
        "user_id" => user_id,
        "import_id" => import_id
      })

  def import_card(repo, user_id, import_id),
    do:
      RailsCommands.insert!(repo, "enhanced_import_card", %{
        "user_id" => user_id,
        "import_id" => import_id
      })

  def visit_months(_repo, _user_id, []), do: :ok

  def visit_months(repo, user_id, started_at) do
    Dawarich.Visits.Calendar.changed(repo, user_id, started_at)
  end

  def orphan_places(_repo, _user_id, []), do: :ok

  def orphan_places(repo, user_id, place_ids),
    do: Dawarich.Places.JobCommands.orphan_places(repo, user_id, place_ids)

  def place_name(repo, user_id, place_id),
    do: Dawarich.Places.JobCommands.name_fetch(repo, user_id, place_id)

  def reverse_place(repo, user_id, place_id),
    do:
      RailsCommands.insert!(repo, "reverse_geocode_place", %{
        "user_id" => user_id,
        "place_id" => place_id
      })
end
