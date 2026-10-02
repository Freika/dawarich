defmodule Dawarich.RailsCache.JsonOrder do
  @moduledoc "Preserves fresh AR JSON insertion order separately from persisted JSONB order."
  def fresh(attrs, activity) do
    patterns = attrs["travel_patterns"]
    time = ordered(patterns["time_of_day"], ~w(night morning afternoon evening))
    pairs = [{"time_of_day", time}]

    pairs =
      if Map.has_key?(patterns, "seasonality"),
        do:
          pairs ++
            [{"seasonality", ordered(patterns["seasonality"], ~w(winter spring summer fall))}],
        else: pairs

    pairs = pairs ++ [{"activity_breakdown", %Jason.OrderedObject{values: activity}}]
    raw = Jason.encode!(%Jason.OrderedObject{values: pairs})
    Map.put(attrs, "_rails_json", %{"travel_patterns" => raw})
  end

  def pattern_pairs(attrs) do
    case get_in(attrs, ["_rails_json", "travel_patterns"]) do
      raw when is_binary(raw) ->
        %Jason.OrderedObject{values: patterns} = Jason.decode!(raw, objects: :ordered_objects)

        for {key, name} <- [
              {"activity_breakdown", :activity_pairs},
              {"time_of_day", :time_pairs},
              {"seasonality", :season_pairs}
            ],
            {^key, %Jason.OrderedObject{values: pairs}} <- [List.keyfind(patterns, key, 0)],
            into: %{},
            do: {name, pairs}

      _ ->
        %{}
    end
  end

  defp ordered(values, keys), do: %Jason.OrderedObject{values: Enum.map(keys, &{&1, values[&1]})}
end
