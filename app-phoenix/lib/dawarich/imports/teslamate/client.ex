defmodule Dawarich.Imports.Teslamate.Client do
  @moduledoc false
  defstruct [
    :url,
    :username,
    :password,
    :api_token,
    skip_ssl_verification: false,
    timeout: 30_000,
    max_attempts: 3
  ]

  def new(url, opts \\ []) do
    url = to_string(url)
    base = if String.ends_with?(url, "/"), do: binary_part(url, 0, byte_size(url) - 1), else: url
    struct!(__MODULE__, Keyword.put(opts, :url, base))
  end

  def cars(client) do
    with {:ok, data} <- get(client, "/api/v1/cars"),
         {:ok, cars} <- collection(data, "cars"),
         do: {:ok, cars}
  end

  def drives(client, car, opts) do
    with {:ok, car} <- positive(car, "resource ID"),
         {:ok, page} <- positive(opts[:page], "page"),
         {:ok, show} <- positive(opts[:show], "show") do
      query = %{page: page, show: show, endDate: DateTime.to_iso8601(opts[:end_date])}

      query =
        if opts[:start_date],
          do: Map.put(query, :startDate, DateTime.to_iso8601(opts[:start_date])),
          else: query

      with {:ok, data} <- get(client, "/api/v1/cars/#{car}/drives?" <> URI.encode_query(query)),
           {:ok, drives} <- collection(data, "drives"),
           do: {:ok, %{drives: drives, units: data["units"] || %{}}}
    end
  end

  def drive(client, car, drive) do
    with {:ok, car} <- positive(car, "resource ID"),
         {:ok, drive} <- positive(drive, "resource ID"),
         {:ok, data} <- get(client, "/api/v1/cars/#{car}/drives/#{drive}") do
      if is_map(data["drive"]),
        do: {:ok, %{drive: data["drive"], units: data["units"] || %{}}},
        else: {:error, "TeslaMateApi response did not contain drive data"}
    end
  end

  defp collection(data, key) do
    if Map.has_key?(data, key) and (is_nil(data[key]) or is_list(data[key])),
      do: {:ok, data[key] || []},
      else: {:error, "TeslaMateApi response did not contain #{key} data"}
  end

  defp get(client, path) do
    case fetch(client, path, 1) do
      {:ok, {{_, status, _}, _, body}} when status in 200..299 -> decode(body)
      {:ok, {{_, status, _}, _, _}} -> {:error, "TeslaMateApi responded with #{status}"}
      {:error, _} -> {:error, "TeslaMateApi connection failed"}
    end
  end

  defp fetch(client, path, attempt) do
    result =
      case Dawarich.Photos.ProviderHTTP.request(
             :get,
             client.url,
             path,
             headers(client),
             nil,
             client.skip_ssl_verification,
             client.timeout
           ) do
        {:ok, status, headers, body} -> {:ok, {{~c"HTTP/1.1", status, ~c""}, headers, body}}
        {:error, reason} -> {:error, reason}
      end

    retry? =
      case result do
        {:ok, {{_, status, _}, _, _}} -> status >= 500
        {:error, _} -> true
      end

    if retry? and attempt < client.max_attempts do
      Process.sleep(if attempt == 1, do: 50, else: 100)
      fetch(client, path, attempt + 1)
    else
      result
    end
  end

  defp headers(client) do
    auth =
      cond do
        present?(client.username) ->
          [
            {~c"authorization",
             String.to_charlist(
               "Basic " <> Base.encode64(client.username <> ":" <> (client.password || ""))
             )}
          ]

        present?(client.api_token) ->
          [{~c"authorization", String.to_charlist("Bearer " <> client.api_token)}]

        true ->
          []
      end

    [{~c"accept", ~c"application/json"} | auth]
  end

  defp decode(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => error}} when error not in [nil, false, "", [], %{}] ->
        {:error, to_string(error)}

      {:ok, %{"data" => data}} when is_map(data) ->
        {:ok, data}

      _ ->
        {:error, "TeslaMateApi returned an invalid response"}
    end
  end

  defp positive(value, label) do
    integer =
      cond do
        is_integer(value) ->
          value

        is_float(value) and value == trunc(value) ->
          trunc(value)

        is_binary(value) ->
          case Integer.parse(String.trim(value)) do
            {number, ""} -> number
            _ -> nil
          end

        true ->
          nil
      end

    if is_integer(integer) and integer > 0,
      do: {:ok, integer},
      else: {:error, "TeslaMateApi #{label} must be a positive integer"}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
