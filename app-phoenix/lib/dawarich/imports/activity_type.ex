defmodule Dawarich.Imports.ActivityType do
  @moduledoc false
  @types %{
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
  def map(nil), do: nil
  def map(value), do: @types[to_string(value)]
end
