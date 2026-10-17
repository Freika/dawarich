defmodule Dawarich.Ingest.OwnTracks do
  @moduledoc false

  alias Dawarich.Ingest.{Geo, Permit, Ruby}
  alias Dawarich.RubyFloat

  @triggers %{
    "p" => "background_event",
    "c" => "circular_region_event",
    "b" => "beacon_event",
    "r" => "report_location_message_event",
    "u" => "manual_event",
    "t" => "timer_based_event",
    "v" => "settings_monitoring_event"
  }
  @connections %{"m" => "mobile", "w" => "wifi", "o" => "offline"}

  def payloads(params) do
    p = Permit.owntracks(params)

    if Ruby.to_s(p["_type"]) != "waypoint" and Ruby.present?(p["lon"]) and Ruby.present?(p["lat"]) and
         Ruby.present?(p["tst"]),
       do: [payload(p)],
       else: []
  end

  defp payload(p) do
    %{
      lonlat: Geo.wkt(p["lon"], p["lat"]),
      battery: p["batt"],
      ping: p["p"],
      altitude: p["alt"],
      accuracy: p["acc"],
      vertical_accuracy: p["vac"],
      velocity: speed(p),
      ssid: p["SSID"],
      bssid: p["BSSID"],
      tracker_id: p["tid"],
      timestamp: Ruby.to_i(p["tst"]),
      inrids: p["inrids"],
      in_regions: p["inregions"],
      topic: p["topic"],
      battery_status: battery_status(p["bs"]),
      connection:
        if(p["conn"] == nil, do: "mobile", else: Map.get(@connections, p["conn"], "unknown")),
      trigger: if(p["t"] == nil, do: "unknown", else: Map.get(@triggers, p["t"], "unknown")),
      motion_data: motion(p),
      raw_data: p,
      altitude_decimal: p["alt"]
    }
  end

  defp speed(p) do
    if Ruby.present?(p["topic"]),
      do: (Ruby.to_f(p["vel"]) * 1000 / 3600) |> RubyFloat.round(1) |> Ruby.to_s(),
      else: p["vel"]
  end

  defp battery_status(nil), do: "unknown"

  defp battery_status(bs) do
    case Ruby.to_i(bs) do
      1 -> "unplugged"
      2 -> "charging"
      3 -> "full"
      _ -> "unknown"
    end
  end

  defp motion(%{"m" => m} = p) when m not in [nil, false],
    do: if(Ruby.truthy?(p["_type"]), do: %{"m" => m, "_type" => p["_type"]}, else: %{"m" => m})

  defp motion(_p), do: %{}
end
