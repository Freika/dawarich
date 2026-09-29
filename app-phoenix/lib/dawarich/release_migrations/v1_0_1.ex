defmodule Dawarich.ReleaseMigrations.V1_0_1 do
  @moduledoc false
  @behaviour Dawarich.ReleaseMigration

  import Dawarich.ReleaseMigration

  @impl true
  def release, do: "1.0.1"

  @impl true
  def data_versions, do: []

  @impl true
  def steps do
    [
      {"20260112192240", &set_existing_users_to_map_v1/1},
      {"20260113230537", &set_points_timestamp_from_geojson_date/1}
    ]
  end

  defp set_existing_users_to_map_v1(repo) do
    sql!(repo, ~S"""
    UPDATE users SET settings = jsonb_set(COALESCE(settings, '{}'), '{maps}', '{}') WHERE NOT (COALESCE(settings, '{}') ? 'maps') AND deleted_at IS NULL;
    UPDATE users SET settings = jsonb_set(settings, '{maps,preferred_version}', '"v1"') WHERE (settings->'maps'->>'preferred_version' IS DISTINCT FROM 'v2') AND deleted_at IS NULL;
    """)
  end

  defp set_points_timestamp_from_geojson_date(repo) do
    sql!(
      repo,
      ~S|UPDATE points SET timestamp = EXTRACT(EPOCH FROM (raw_data->'properties'->>'date')::timestamptz)::bigint WHERE timestamp IS NULL AND raw_data IS NOT NULL AND raw_data ? 'properties' AND raw_data->'properties' ? 'date' AND (raw_data->'properties'->>'date') ~ '^[0-9]{4}-';|
    )
  end
end
