defmodule Dawarich.Places.NearbyInput do
  @moduledoc false
  alias Dawarich.Places.WebWrite

  def parse(params) when is_map(params) do
    with {:ok, lat} <- coordinate(params["latitude"], 90),
         {:ok, lon} <- coordinate(params["longitude"], 180),
         {:ok, radius} <- radius(Map.get(params, "radius", "0.5")),
         {:ok, limit} <- limit(Map.get(params, "limit", "5")) do
      {:ok, %{latitude: lat, longitude: lon, radius: radius, limit: limit}}
    else
      _ -> {:error, :invalid_input}
    end
  rescue
    _ -> {:error, :invalid_input}
  end

  def parse(_), do: {:error, :invalid_input}

  defp coordinate(value, max) when is_number(value), do: coordinate(to_string(value), max)

  defp coordinate(value, max) when is_binary(value) and byte_size(value) <= 128 do
    case WebWrite.coordinate(value, max) do
      v when is_number(v) -> {:ok, elem(Float.parse(value), 0)}
      _ -> :error
    end
  end

  defp coordinate(_, _), do: :error

  defp radius(value) do
    case coordinate(value, 1.5) do
      {:ok, number} when number in [0.5, 1.0, 1.5] -> {:ok, number}
      _ -> :error
    end
  end

  defp limit(value) when is_integer(value) and value in 1..5, do: {:ok, value}
  defp limit(value) when value in ~w(1 2 3 4 5), do: {:ok, String.to_integer(value)}
  defp limit(_), do: :error
end
