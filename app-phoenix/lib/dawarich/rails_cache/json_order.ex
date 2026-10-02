defmodule Dawarich.RailsCache.JsonOrder do
  @moduledoc "Key order of a digest's travel_patterns JSON, as cached by Rails or stored in JSONB."
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
end
