defmodule Dawarich.Photos.ThumbnailClosure do
  @moduledoc false
  alias Dawarich.Photos.{Index, ProviderCache}

  def fetch(settings, source, id, user) do
    escaped = URI.encode(id, &URI.char_unreserved?/1)
    {path, headers} = request(source, escaped, settings, user)

    result =
      get(
        settings[source <> "_url"],
        path,
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

  defp get(base, path, headers, skip, attempts) do
    case Index.request(:get, base, path, headers, nil, skip) do
      {:ok, status, _, body} when status in 200..299 -> {:ok, body}
      {:ok, 403, _, body} -> {:error, 403, body}
      {:ok, status, _, _} -> {:error, status}
      {:error, :timeout} when attempts > 1 -> get(base, path, headers, skip, attempts - 1)
      {:error, _} -> :timeout
    end
  end
end
