defmodule Dawarich.Address do
  @moduledoc false
  alias Dawarich.Geocoding.Normalizer
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def place(data) do
    props = Normalizer.from_data(data).properties

    join(
      [
        join([props["street"], props["housenumber"]], " "),
        join([props["postcode"], props["city"]], " ")
      ],
      ", "
    )
  end

  def point(data) do
    props = Normalizer.from_data(data).properties
    join(Enum.map(~w(street city country), &props[&1]), ", ")
  end

  def manual(%{} = address) do
    props =
      for {source, target} <- [
            {"street", "street"},
            {"house_number", "housenumber"},
            {"postcode", "postcode"},
            {"city", "city"},
            {"country", "country"}
          ],
          value = address[source],
          is_binary(value) or is_number(value) or is_boolean(value),
          Ruby.present?(value),
          into: %{},
          do: {target, value}

    if props == %{}, do: %{}, else: %{"properties" => props}
  end

  def manual(_), do: %{}

  def value(data, key) do
    case get_in(data, ["properties", key]) do
      nil -> nil
      true -> "t"
      value -> to_string(value)
    end
  end

  defp join(values, separator) do
    case values |> Enum.reject(&Ruby.blank?/1) |> Enum.join(separator) do
      "" -> nil
      text -> text
    end
  end
end
