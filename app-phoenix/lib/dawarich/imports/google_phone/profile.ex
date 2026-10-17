defmodule Dawarich.Imports.GooglePhone.Profile do
  @moduledoc false
  alias Dawarich.Imports.{ImportTime, ZonePeriod}
  alias Dawarich.Imports.GooglePhone.{Coordinates, Points}
  alias Dawarich.Ingest.Ruby

  def prepare(profile, reference, import, context) do
    places =
      if is_map(profile),
        do: profile["frequentPlaces"],
        else: raise(ArgumentError, "profile is not a hash")

    if Ruby.blank?(places) do
      []
    else
      base = midnight(reference, context)
      unless is_list(places), do: raise(ArgumentError, "frequentPlaces is not an array")

      Enum.with_index(places)
      |> Enum.flat_map(fn {place, index} ->
        case Coordinates.parse(place["placeLocation"]) do
          nil ->
            []

          coordinate ->
            raw = %{"frequent_place_label" => place["label"], "placeId" => place["placeId"]}

            case Points.point(coordinate, base + index, raw, context) do
              nil ->
                []

              attrs ->
                now = clock(context.now) |> DateTime.to_naive()

                [
                  Map.merge(attrs, %{
                    import_id: import.id,
                    user_id: import.user_id,
                    created_at: now,
                    updated_at: now,
                    topic: "Google Maps Phone Timeline Export",
                    tracker_id: "google-phone-#{import.id}"
                  })
                ]
            end
        end
      end)
    end
  end

  defp midnight(reference, context) do
    if Ruby.truthy?(reference) do
      unless is_binary(reference), do: raise(ArgumentError, "date must be a string")
      parts = Dawarich.Imports.DateParts.parse(reference)
      if parts == %{}, do: raise(ArgumentError, "invalid date")
      midnight = Map.put(parts, "hour", 0) |> Map.put("min", 0) |> Map.put("sec", 0)
      year = midnight["year"] || clock(context.now).year
      month = midnight["mon"] || clock(context.now).month
      day = midnight["mday"] || clock(context.now).day
      text = "#{year}-#{month}-#{day}T00:00:00"
      offset = parts["offset"] || 0
      stamp = ImportTime.parse(text <> "Z", "Etc/UTC", clock(context.now), context.repo)
      stamp - offset_value(offset)
    else
      zone = ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(context.zone))
      local = ZonePeriod.local_now(zone, clock(context.now))
      ZonePeriod.resolve(zone, NaiveDateTime.new!(NaiveDateTime.to_date(local), ~T[00:00:00]))
    end
  end

  defp offset_value(%{"numerator" => n, "denominator" => d}), do: Integer.floor_div(n, d)
  defp offset_value(value), do: value
  defp clock(fun) when is_function(fun, 0), do: clock(fun.())
  defp clock(%NaiveDateTime{} = value), do: DateTime.from_naive!(value, "Etc/UTC")
  defp clock(%DateTime{} = value), do: value
end
