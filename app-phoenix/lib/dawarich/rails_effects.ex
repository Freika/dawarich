defmodule Dawarich.RailsEffects do
  @moduledoc false

  alias Dawarich.RailsCommands

  def tile_epoch(repo, user_id, timestamps),
    do:
      RailsCommands.insert!(repo, "points.tile_epoch", %{
        "user_id" => user_id,
        "timestamps" => timestamps
      })

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
    stamps = started_at |> Enum.map(&DateTime.to_iso8601/1) |> Enum.uniq()

    RailsCommands.insert!(repo, "visit_months_changed", %{
      "user_id" => user_id,
      "started_at" => stamps
    })
  end

  def orphan_places(_repo, _user_id, []), do: :ok

  def orphan_places(repo, user_id, place_ids),
    do:
      RailsCommands.insert!(repo, "places_delete_if_orphan", %{
        "user_id" => user_id,
        "place_ids" => Enum.uniq(place_ids)
      })

  def place_name(repo, user_id, place_id),
    do:
      RailsCommands.insert!(repo, "place_name_fetch", %{
        "user_id" => user_id,
        "place_id" => place_id
      })

  def reverse_place(repo, user_id, place_id),
    do:
      RailsCommands.insert!(repo, "reverse_geocode_place", %{
        "user_id" => user_id,
        "place_id" => place_id
      })
end
