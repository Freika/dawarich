defmodule DawarichWeb.MapLive.Coordinates do
  @moduledoc false

  def normalize(params) do
    with {:ok, latitude} <- coordinate(params["latitude"], 90),
         {:ok, longitude} <- coordinate(params["longitude"], 180) do
      {:ok, %{"latitude" => latitude, "longitude" => longitude}}
    end
  end

  defp coordinate(value, limit) when is_number(value) and value >= -limit and value <= limit,
    do: {:ok, to_string(value)}

  defp coordinate(value, limit) when is_binary(value) and byte_size(value) <= 64 do
    case Float.parse(value) do
      {number, ""} when number >= -limit and number <= limit -> {:ok, value}
      _ -> {:error, :invalid_coordinates}
    end
  end

  defp coordinate(_, _), do: {:error, :invalid_coordinates}
end
