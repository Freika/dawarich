defmodule Dawarich.Photos.ThumbnailClosure do
  @moduledoc false
  alias Dawarich.Photos.{Index, ProviderCache}

  def fetch(settings, source, id, user) do
    escaped = URI.encode(id, &URI.char_unreserved?/1)
    {path, headers} = request(source, escaped, settings, user)

    result =
      get(
        to_string(settings[source <> "_url"]) <> path,
        headers,
        settings[source <> "_skip_ssl_verification"],
        2
      )

    case result do
      {:error, 403, body} -> permission(source, body)
      other -> other
    end
  rescue
    _ -> {:error, 500}
  end

  def http(method, url, headers, body, skip) do
    headers = for {k, v} <- headers, do: {String.to_charlist(k), String.to_charlist(v)}

    request =
      if body,
        do: {String.to_charlist(url), headers, ~c"application/json", body},
        else: {String.to_charlist(url), headers}

    timeout = Application.get_env(:dawarich, :photo_source_timeout, 10_000)

    case :httpc.request(
           method,
           request,
           [timeout: timeout, connect_timeout: timeout, ssl: Dawarich.Photos.Thumbnail.ssl(skip)],
           body_format: :binary
         ) do
      {:ok, {{_, status, reason}, headers, raw}} ->
        {:ok, status, [{"_status_reason", to_string(reason)} | headers], raw}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, :transport}
  end

  defp permission("immich", body) do
    with {:ok, data} <- Jason.decode(body),
         message when is_binary(message) <- data["message"],
         true <- String.contains?(message, "asset.view"),
         do: {:error, 403, :permission_missing},
         else: (_ -> {:error, 403})
  end

  defp permission(_, _), do: {:error, 403}

  defp request("photoprism", id, _settings, user) do
    token = ProviderCache.token(user)
    {"/api/v1/t/#{id}/#{token}/tile_500", [{"accept", "application/octet-stream"}]}
  end

  defp request("immich", id, settings, _user),
    do:
      {"/api/assets/#{id}/thumbnail?size=preview",
       [{"accept", "application/octet-stream"}, {"x-api-key", settings["immich_api_key"]}]}

  defp get(url, headers, skip, attempts) do
    case Index.request(:get, url, headers, nil, skip) do
      {:ok, status, _, body} when status in 200..299 -> {:ok, body}
      {:ok, 403, _, body} -> {:error, 403, body}
      {:ok, status, _, _} -> {:error, status}
      {:error, :timeout} when attempts > 1 -> get(url, headers, skip, attempts - 1)
      {:error, _} -> :timeout
    end
  end
end
