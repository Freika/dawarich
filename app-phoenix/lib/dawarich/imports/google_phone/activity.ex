defmodule Dawarich.Imports.GooglePhone.Activity do
  @moduledoc false
  alias Dawarich.Ingest.Ruby

  @mapping %{
    "IN_PASSENGER_VEHICLE" => "driving",
    "WALKING" => "walking",
    "CYCLING" => "cycling",
    "RUNNING" => "running",
    "FLYING" => "flying",
    "IN_BUS" => "bus",
    "IN_TRAIN" => "train",
    "Running" => "running",
    "Biking" => "cycling",
    "running" => "running",
    "trail_running" => "running",
    "cycling" => "cycling",
    "mountain_biking" => "cycling",
    "walking" => "walking",
    "hiking" => "walking",
    "driving" => "driving",
    "flying" => "flying"
  }

  def type(value), do: @mapping[Ruby.to_s(value)]

  def motion(raw, type) do
    record = raw["activityRecord"]
    activities = if Ruby.truthy?(record), do: field(record, "probableActivities")

    result =
      if Ruby.truthy?(activities),
        do: %{"activityRecord" => %{"probableActivities" => activities}},
        else: %{}

    result =
      if Ruby.truthy?(raw["activity"]),
        do: Map.put(result, "activity", raw["activity"]),
        else: result

    if Ruby.truthy?(type), do: Map.put(result, "activity_type", type), else: result
  end

  defp field(value, key) when is_map(value), do: value[key]
  defp field(_, _), do: raise(ArgumentError, "activityRecord is not a hash")
end
