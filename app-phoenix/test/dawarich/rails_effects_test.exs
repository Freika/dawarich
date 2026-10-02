defmodule Dawarich.RailsEffectsTest do
  use Dawarich.JobsCase

  alias Dawarich.RailsEffects

  test "each builder writes one row; empty lists write none" do
    assert RailsEffects.tile_epoch(ScratchRepo, 1, [111, 222]) == :ok
    assert RailsEffects.untracked_tracks(ScratchRepo, 1, 5) == :ok
    assert RailsEffects.import_card(ScratchRepo, 1, 5) == :ok
    assert RailsEffects.visit_months(ScratchRepo, 1, [~U[2026-06-15 10:00:00Z]]) == :ok
    assert RailsEffects.orphan_places(ScratchRepo, 1, [9, 9, 10]) == :ok
    assert RailsEffects.place_name(ScratchRepo, 1, 9) == :ok
    assert RailsEffects.reverse_place(ScratchRepo, 1, 9) == :ok

    assert rows("SELECT kind, payload FROM phoenix.rails_commands ORDER BY id") == [
             ["points.tile_epoch", %{"user_id" => 1, "timestamps" => [111, 222]}],
             ["schedule_untracked_tracks", %{"user_id" => 1, "import_id" => 5}],
             ["enhanced_import_card", %{"user_id" => 1, "import_id" => 5}],
             [
               "visit_months_changed",
               %{"user_id" => 1, "started_at" => ["2026-06-15T10:00:00Z"]}
             ],
             ["places_delete_if_orphan", %{"user_id" => 1, "place_ids" => [9, 10]}],
             ["place_name_fetch", %{"user_id" => 1, "place_id" => 9}],
             ["reverse_geocode_place", %{"user_id" => 1, "place_id" => 9}]
           ]

    assert RailsEffects.visit_months(ScratchRepo, 1, []) == :ok
    assert RailsEffects.orphan_places(ScratchRepo, 1, []) == :ok

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[7]]
  end
end
