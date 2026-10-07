defmodule Dawarich.EnhancedImport.SemanticAdapter do
  @moduledoc false
  alias Dawarich.EnhancedImport.AdapterFields, as: Fields
  alias Dawarich.Imports.JsonStream.Section
  @source "google_semantic_history"

  def reduce(path, import, context, acc, fun) do
    {root, section} = Section.last(path, "timelineObjects")
    unless root.kind == :object, do: raise(ArgumentError, "Timeline must be an object")

    Section.reduce(path, section, acc, fn object, acc ->
      object = Fields.plain(object)
      unless is_map(object), do: raise(ArgumentError, "Timeline entry must be an object")

      cond do
        object["placeVisit"] ->
          Fields.emit(visit(object["placeVisit"], context), acc, fun)

        object["activitySegment"] ->
          Fields.emit(track(object["activitySegment"], import, context), acc, fun)

        true ->
          acc
      end
    end)
  end

  defp visit(visit, context) do
    location = visit["location"]

    if Fields.presence(location) && Fields.presence(location["placeId"]) do
      latitude = Fields.e7(location["latitudeE7"])
      longitude = Fields.e7(location["longitudeE7"])
      duration = visit["duration"] || %{}
      first = duration_time(duration, "start", context)
      last = duration_time(duration, "end", context)

      if latitude && longitude && first && last do
        place =
          Fields.place(
            "google:#{location["placeId"]}",
            Fields.presence(location["name"]) || Fields.humanize(location["semanticType"]) ||
              "Unknown",
            latitude,
            longitude,
            location["semanticType"]
          )

        Fields.visit(place, first, last, visit["visitConfidence"], @source)
      end
    end
  end

  defp track(activity, import, context) do
    duration = activity["duration"] || %{}
    first = duration_time(duration, "start", context)
    last = duration_time(duration, "end", context)

    Fields.track(
      import,
      first,
      last,
      activity["activityType"],
      activity["distance"],
      activity["confidence"],
      @source
    )
  end

  defp duration_time(duration, prefix, context) do
    Fields.time(duration[prefix <> "Timestamp"], context) ||
      Fields.epoch_ms(duration[prefix <> "TimestampMs"], context)
  end
end
