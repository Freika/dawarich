defmodule Dawarich.Transportation.HintScorer do
  @moduledoc false

  @google_mode_map %{
    "STILL" => "stationary",
    "WALKING" => "walking",
    "ON_FOOT" => "walking",
    "RUNNING" => "running",
    "CYCLING" => "cycling",
    "ON_BICYCLE" => "cycling",
    "IN_VEHICLE" => "driving",
    "IN_ROAD_VEHICLE" => "driving",
    "DRIVING" => "driving",
    "IN_RAIL_VEHICLE" => "train",
    "IN_BUS" => "bus",
    "BUS" => "bus",
    "IN_SUBWAY" => "train",
    "IN_TRAM" => "train",
    "IN_TRAIN" => "train",
    "TRAIN" => "train",
    "IN_FERRY" => "boat",
    "SAILING" => "boat",
    "FLYING" => "flying",
    "IN_AIRPLANE" => "flying",
    "MOTORCYCLING" => "motorcycle"
  }

  @overland_mode_map %{
    "driving" => "driving",
    "automotive" => "driving",
    "walking" => "walking",
    "running" => "running",
    "cycling" => "cycling",
    "stationary" => "stationary"
  }

  @default_probability 0.6
  @probability_scale 8.0
  @generic_vehicle_hints ["IN_VEHICLE", "AUTOMOTIVE"]
  @train_share_of_vehicle_hint 0.7

  def call(motion_data) when is_map(motion_data) and map_size(motion_data) > 0 do
    hints = google_hints(motion_data)
    if hints == [], do: overland_hints(motion_data), else: hints
  end

  def call(_motion_data), do: []

  defp google_hints(data) do
    activity_record = data["activityRecord"]

    activities =
      cond do
        is_map(activity_record) and is_list(activity_record["probableActivities"]) ->
          activity_record["probableActivities"]

        is_list(data["activities"]) ->
          data["activities"]

        true ->
          nil
      end

    if activities do
      from_probable_activities(activities)
    else
      google_hints_from_type(data)
    end
  end

  defp google_hints_from_type(data) do
    type = data["activityType"] || data["travelMode"] || data["activity"]

    if is_binary(type) do
      case Map.get(@google_mode_map, String.upcase(type)) do
        nil -> []
        mode -> expand_generic_vehicle([{mode, boost(@default_probability)}], type)
      end
    else
      []
    end
  end

  defp from_probable_activities(activities) do
    activities
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.reduce([], fn activity, acc ->
      type = activity["activityType"] || activity["type"]
      mode = type && Map.get(@google_mode_map, type |> to_string() |> String.upcase())

      case mode do
        nil ->
          acc

        _ ->
          probability =
            to_float(activity["probability"] || activity["confidence"] || @default_probability)

          put_max(acc, mode, boost(probability))
      end
    end)
    |> strongest_only()
  end

  defp overland_hints(data) do
    case data["motion"] do
      motion when is_list(motion) ->
        raw_entries = Enum.map(motion, &(&1 |> to_string() |> String.downcase()))

        hints =
          Enum.reduce(raw_entries, [], fn entry, acc ->
            case Map.get(@overland_mode_map, entry) do
              nil -> acc
              mode -> put(acc, mode, overland_boost())
            end
          end)

        generic =
          Enum.find(raw_entries, fn e ->
            String.upcase(e) in @generic_vehicle_hints or e == "driving"
          end) || ""

        expand_generic_vehicle(strongest_only(hints), generic)

      _ ->
        []
    end
  end

  defp overland_boost, do: :math.log(9)

  defp strongest_only(hints) when length(hints) <= 1, do: hints

  defp strongest_only(hints) do
    {mode, value} =
      Enum.reduce(hints, nil, fn {mode, value}, best ->
        case best do
          nil -> {mode, value}
          {_best_mode, best_value} -> if value > best_value, do: {mode, value}, else: best
        end
      end)

    [{mode, value}]
  end

  defp expand_generic_vehicle(hints, source_type) do
    driving_boost = get_value(hints, "driving")

    if is_nil(driving_boost) or not generic_vehicle_source?(source_type) do
      hints
    else
      candidate = driving_boost * @train_share_of_vehicle_hint

      new_value =
        case get_value(hints, "train") do
          nil -> candidate
          existing -> max(existing, candidate)
        end

      put(hints, "train", new_value)
    end
  end

  defp get_value(list, mode) do
    case List.keyfind(list, mode, 0) do
      {^mode, value} -> value
      nil -> nil
    end
  end

  defp put(list, mode, value) do
    case List.keyfind(list, mode, 0) do
      {^mode, _} -> List.keyreplace(list, mode, 0, {mode, value})
      nil -> list ++ [{mode, value}]
    end
  end

  defp put_max(list, mode, value) do
    case List.keyfind(list, mode, 0) do
      {^mode, existing} -> List.keyreplace(list, mode, 0, {mode, max(existing, value)})
      nil -> list ++ [{mode, value}]
    end
  end

  defp generic_vehicle_source?(source_type) do
    normalized = source_type |> to_string() |> String.upcase()

    normalized in @generic_vehicle_hints or
      normalized in ["DRIVING", "OTHER_NAVIGATION", "AUTOMOTIVE_NAVIGATION"]
  end

  defp boost(probability) do
    clamped = probability |> max(0.0) |> min(1.0)
    :math.log(1 + @probability_scale * clamped)
  end

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0
end
