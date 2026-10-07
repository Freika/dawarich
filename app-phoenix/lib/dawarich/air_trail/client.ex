defmodule Dawarich.AirTrail.Client do
  @moduledoc false

  def flights(%{url: url, api_key: api_key, skip_ssl_verification: skip}) do
    base = if String.ends_with?(url, "/"), do: binary_part(url, 0, byte_size(url) - 1), else: url

    headers = [
      {"authorization", "Bearer " <> api_key},
      {"accept", "application/json"},
      {"connection", "close"}
    ]

    case Dawarich.Photos.ProviderHTTP.request(
           :get,
           base,
           "/api/flight/list?scope=mine",
           headers,
           nil,
           skip,
           15_000
         ) do
      {:ok, status, _headers, body} when status in 200..299 -> decode(body)
      {:ok, status, _headers, _body} -> {:error, "AirTrail responded with #{status}"}
      {:error, reason} -> {:error, connection_message(reason)}
    end
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, %{"success" => success} = decoded} when success not in [nil, false] ->
        flights_list(decoded["flights"])

      {:ok, _other} ->
        {:error, "AirTrail returned an unsuccessful response"}

      {:error, _reason} ->
        {:error, "AirTrail returned invalid JSON"}
    end
  end

  defp flights_list(nil), do: {:ok, []}

  defp flights_list(flights) when is_list(flights) do
    if Enum.all?(flights, &is_map/1),
      do: {:ok, flights},
      else: {:error, "AirTrail returned an unsuccessful response"}
  end

  defp flights_list(_other), do: {:error, "AirTrail returned an unsuccessful response"}

  defp connection_message(:timeout), do: "AirTrail request timed out"
  defp connection_message(:connection), do: "Could not connect to AirTrail"
  defp connection_message(_reason), do: "AirTrail request failed"
end
