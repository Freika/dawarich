defmodule Dawarich.Imports.Fit.Point do
  @moduledoc false
  alias Dawarich.Imports.ActivityType
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  def build(record, sport, import, context) do
    lat = record["position_lat"]
    lon = record["position_long"]

    if not is_nil(lat) and not is_nil(lon) do
      type = ActivityType.map(sport)
      now = if is_function(context.now, 0), do: context.now.(), else: context.now
      speed = record["enhanced_speed"] || record["speed"]

      attrs = %{
        lonlat: "POINT(#{RubyFloat.to_s(lon)} #{RubyFloat.to_s(lat)})",
        timestamp: record["timestamp"] || 0,
        altitude: record["altitude"],
        velocity: if(is_nil(speed), do: nil, else: Float.round(speed, 1)),
        user_id: import.user_id,
        import_id: import.id,
        motion_data: if(type, do: %{"activity_type" => type}, else: %{}),
        created_at: now,
        updated_at: now
      }

      if Map.get(context, :altitude_decimal?, true),
        do: Map.put(attrs, :altitude_decimal, record["altitude"]),
        else: attrs
    end
  end
end
