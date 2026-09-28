defmodule Dawarich.AirTrail.Client do
  @moduledoc false

  def flights(%{url: url, api_key: api_key, skip_ssl_verification: skip}) do
    base = if String.ends_with?(url, "/"), do: binary_part(url, 0, byte_size(url) - 1), else: url
    target = base <> "/api/flight/list?scope=mine"

    request =
      {String.to_charlist(target),
       [
         {~c"authorization", String.to_charlist("Bearer " <> api_key)},
         {~c"accept", ~c"application/json"}
       ]}

    options = [connect_timeout: 15_000, timeout: 15_000, ssl: ssl(target, skip)]

    case :httpc.request(:get, request, options, body_format: :binary) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 -> decode(body)
      {:ok, {{_, status, _}, _headers, _body}} -> {:error, "AirTrail responded with #{status}"}
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

  defp ssl(_target, true), do: [verify: :verify_none]
  defp ssl(target, false), do: Dawarich.Http.ssl_options(target)

  defp connection_message(reason) when reason in [:timeout, :connect_timeout],
    do: "AirTrail request timed out"

  defp connection_message({:failed_connect, _details}), do: "Could not connect to AirTrail"
  defp connection_message(_reason), do: "AirTrail request failed"
end
