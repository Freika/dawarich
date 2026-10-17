defmodule Dawarich.Imports.Trek.Payload do
  @moduledoc false
  alias Dawarich.Imports.Trek.Client.Error
  alias Dawarich.Ingest.Ruby

  def normalize(payload) do
    required_keys!(payload, ~w(start_date end_date), "trip")

    if is_nil(payload["start_date"]) or is_nil(payload["end_date"]),
      do:
        raise(Error,
          kind: :undated,
          message: "TREK trip needs start and end dates before it can be imported"
        )

    required!(payload, ~w(start_date end_date), "trip")
    from = date!(payload["start_date"], "trip start_date")
    to = date!(payload["end_date"], "trip end_date")
    if Date.compare(to, from) == :lt, do: invalid!("trip end_date precedes start_date")

    dates =
      for day <- collection!(payload, "days") do
        required!(day, ~w(date day_number), "day")
        date = date!(day["date"], "day date")

        if Date.compare(date, from) == :lt or Date.compare(date, to) == :gt,
          do: invalid!("day date falls outside the trip range")

        if integer!(day["day_number"], "day number") <= 0, do: invalid!("day number is invalid")
        places!(day, "places", "place")
        named!(day, "day_notes", "day note", "text")
        named!(day, "reservations", "reservation", nil)
        date
      end

    if length(Enum.uniq(dates)) != length(dates), do: invalid!("days contain duplicate dates")
    named!(payload, "unscheduled_reservations", "reservation", nil)

    for accommodation <- collection!(payload, "accommodations") do
      unless is_map(accommodation), do: invalid!("accommodation must be an object")
      coordinates!(accommodation, "accommodation")
      from = optional_date!(accommodation["start_date"], "accommodation start_date")
      to = optional_date!(accommodation["end_date"], "accommodation end_date")

      if from && to && Date.compare(to, from) == :lt,
        do: invalid!("accommodation end_date precedes start_date")
    end

    named!(payload, "travellers", "traveller", "name")
    places!(payload, "unplanned_places", "unplanned place")
    payload
  end

  def digest(payload),
    do:
      :crypto.hash(:sha256, Dawarich.RubyJson.encode_exact!(canonical(payload)))
      |> Base.encode16(case: :lower)

  def canonical(map) when is_map(map),
    do:
      map
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> {k, canonical(v)} end)
      |> Jason.OrderedObject.new()

  def canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  def canonical(value), do: value

  def collection!(map, key) do
    case map[key] do
      nil -> []
      list when is_list(list) -> list
      _ -> invalid!("#{key} must be an array")
    end
  end

  def integer!(value, _field) when is_integer(value), do: value

  def integer!(value, field) when is_binary(value) do
    if Regex.match?(~r/\A[+-]?\d+\z/, value),
      do: String.to_integer(value),
      else: invalid!("#{field} is invalid")
  end

  def integer!(_, field), do: invalid!("#{field} is invalid")

  def date!(value, field) do
    case Date.from_iso8601(to_string(value)) do
      {:ok, date} -> date
      _ -> invalid!("#{field} is invalid")
    end
  rescue
    _ -> invalid!("#{field} is invalid")
  end

  defp optional_date!(nil, _), do: nil
  defp optional_date!(value, field), do: date!(value, field)

  defp required_keys!(map, fields, name) do
    unless is_map(map), do: invalid!("#{name} must be an object")
    missing = Enum.reject(fields, &Map.has_key?(map, &1))

    if missing != [],
      do: invalid!("#{name} is missing required fields: #{Enum.join(missing, ", ")}")
  end

  defp required!(map, fields, name) do
    unless is_map(map), do: invalid!("#{name} must be an object")
    missing = Enum.filter(fields, &Ruby.blank?(map[&1]))

    if missing != [],
      do: invalid!("#{name} is missing required fields: #{Enum.join(missing, ", ")}")

    unless Enum.all?(fields, fn f -> is_binary(map[f]) or is_number(map[f]) end),
      do: invalid!("#{name} contains invalid fields")
  end

  defp named!(map, collection, name, field) do
    for item <- collection!(map, collection),
        do: required!(item, if(field, do: [field], else: []), name)
  end

  defp places!(map, collection, name) do
    for place <- collection!(map, collection) do
      required!(place, ["name"], name)
      coordinates!(place, name)

      if place["duration_minutes"] != nil and
           integer!(place["duration_minutes"], "#{name} duration_minutes") < 0,
         do: invalid!("#{name} duration_minutes is invalid")
    end
  end

  defp coordinates!(map, name) do
    lat = map["lat"]
    lon = map["lng"]

    unless is_nil(lat) and is_nil(lon) do
      if is_nil(lat) or is_nil(lon), do: invalid!("#{name} coordinates are incomplete")
      number!(lat, -90, 90, "#{name} latitude")
      number!(lon, -180, 180, "#{name} longitude")
    end
  end

  defp number!(value, min, max, field) do
    number =
      case value do
        n when is_number(n) ->
          n

        v when is_binary(v) ->
          case Float.parse(String.trim(v)) do
            {n, ""} -> n
            _ -> nil
          end

        _ ->
          nil
      end

    unless is_number(number) and number >= min and number <= max,
      do: invalid!("#{field} is invalid")
  end

  defp invalid!(message),
    do:
      raise(Error, kind: :invalid_payload, message: "TREK trip response is invalid: " <> message)
end
