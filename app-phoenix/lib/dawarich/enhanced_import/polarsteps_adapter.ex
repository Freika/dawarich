defmodule Dawarich.EnhancedImport.PolarstepsAdapter do
  @moduledoc false
  alias Dawarich.EnhancedImport.AdapterFields, as: Fields
  alias Dawarich.Imports.JsonStream.Section
  @source "polarsteps"

  def reduce(path, _import, context, acc, fun) do
    {root, section} = Section.last(path, "steps")
    section = if root.kind == :array, do: root, else: section

    Section.reduce(path, section, acc, fn step, acc ->
      Fields.emit(visit(Fields.plain(step), context), acc, fun)
    end)
  end

  defp visit(step, context) when is_map(step) do
    location = step["location"]
    location = if !Fields.presence(location) && step["lat"], do: step, else: location

    if Fields.presence(location) do
      latitude = Fields.float(location["lat"])
      longitude = Fields.float(location["lon"] || location["lng"])
      first = Fields.unix(step["arrived"] || step["start_time"], context)
      last = Fields.unix(step["departed"] || step["end_time"], context)

      if latitude && longitude && first && last do
        name =
          Fields.presence(step["display_name"]) || Fields.presence(step["name"]) ||
            Fields.presence(location["detail"]) || "Unknown"

        place =
          Fields.place("polarsteps:#{step["id"]}", name, latitude, longitude, "polarsteps_step")

        Fields.visit(place, first, last, nil, @source)
      end
    end
  end

  defp visit(_, _), do: nil
end
