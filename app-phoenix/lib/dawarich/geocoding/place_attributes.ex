defmodule Dawarich.Geocoding.PlaceAttributes do
  @moduledoc false

  alias Dawarich.{RubyDecimal, RubyFloat}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @default_name "Suggested place"
  @identity_keys ~w(external_place_id semantic_type)
  @indexed_keys ~w(osm_id osm_type osm_key osm_value)

  def populate(place, data, store_geodata) do
    props = properties!(data)

    place =
      if place.name_locked,
        do: place,
        else: %{place | name: name(data), source: if(place.source == 2, do: 2, else: 1)}

    %{
      place
      | city: cast!(props["city"]),
        country: cast!(props["country"]),
        geodata: geodata(place.geodata, data, store_geodata)
    }
  end

  def fill_lonlat(%{x: nil} = place, data) do
    {x, y} = coordinates!(data)
    %{place | x: x, y: y}
  end

  def fill_lonlat(place, _data), do: place

  def queried_coordinates!(data) do
    case data["geometry"] do
      %{"coordinates" => coordinates} when coordinates not in [nil, false] -> :ok
      _ -> raise ArgumentError, "the geocoder result has no coordinates"
    end
  end

  def new_place(user_id, data) do
    {x, y} = coordinates!(data)

    %{
      id: nil,
      user_id: user_id,
      name: nil,
      name_locked: false,
      source: 0,
      latitude: RubyDecimal.column(RubyFloat.round(y, 5), 10, 6),
      longitude: RubyDecimal.column(RubyFloat.round(x, 5), 10, 6),
      x: x,
      y: y,
      geodata: %{},
      city: nil,
      country: nil
    }
  end

  def name(data) do
    props = properties!(data)
    name = meaningful(props["name"])
    type = meaningful(props["osm_value"])
    type = if type, do: type |> String.capitalize() |> String.replace("_", " ") |> presence()

    address = Ruby.strip(to_s(props["postcode"]) <> " " <> to_s(props["street"]))

    address =
      if Ruby.present?(props["housenumber"]),
        do: address <> " " <> to_s(props["housenumber"]),
        else: address

    name = name || presence(address) || @default_name
    if type, do: "#{name} (#{type})", else: name
  end

  def geodata(existing, data, store_geodata) do
    identity = if is_map(existing), do: Map.take(existing, @identity_keys), else: %{}

    if store_geodata do
      Map.merge(data, identity)
    else
      indexed =
        for {key, value} <- Map.take(data["properties"] || %{}, @indexed_keys),
            not is_nil(value),
            into: %{},
            do: {key, value}

      Map.put(identity, "properties", indexed)
    end
  end

  def validate_name!(name) do
    cond do
      Ruby.blank?(name) -> raise ArgumentError, "Name can't be blank"
      length(String.to_charlist(name)) > 255 -> raise ArgumentError, "Name is too long"
      true -> name
    end
  end

  def osm_key(data) do
    case data["properties"] do
      %{} = props -> to_s(props["osm_id"])
      nil -> ""
      other -> raise ArgumentError, "properties is not a Hash: #{inspect(other)}"
    end
  end

  def osm_id(%{geodata: %{"properties" => %{} = props}}), do: props["osm_id"]
  def osm_id(_place), do: nil

  def coordinates!(data) do
    case data["geometry"] do
      %{"coordinates" => [x, y | _]} when is_number(x) and is_number(y) -> {x * 1.0, y * 1.0}
      _ -> raise ArgumentError, "the geocoder result has no coordinates"
    end
  end

  def cast!(nil), do: nil
  def cast!(value) when is_binary(value), do: value
  def cast!(true), do: "t"
  def cast!(false), do: "f"
  def cast!(value) when is_integer(value), do: Integer.to_string(value)
  def cast!(value) when is_float(value), do: Ruby.to_s(value)
  def cast!(value), do: raise(ArgumentError, "unsupported place value #{inspect(value)}")

  defp properties!(data) do
    case data["properties"] do
      %{} = props -> props
      _ -> raise ArgumentError, "the geocoder result has no properties"
    end
  end

  defp meaningful(value) do
    normalized = Ruby.strip(to_s(value))

    if Ruby.blank?(normalized) or String.downcase(normalized) in ["yes", "no"],
      do: nil,
      else: normalized
  end

  defp presence(value), do: if(Ruby.present?(value), do: value)

  defp to_s(nil), do: ""
  defp to_s(value), do: Ruby.to_s(value)
end
