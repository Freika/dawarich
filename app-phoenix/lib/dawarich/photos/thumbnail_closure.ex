defmodule Dawarich.Photos.ThumbnailClosure do
  @moduledoc false
  alias Dawarich.Photos.{Index, ProviderCache}

  def fetch(settings, source, id, user) do
    escaped = URI.encode(id, &URI.char_unreserved?/1)
    {path, headers} = request(source, escaped, settings, user)

    get(
      settings[source <> "_url"] <> path,
      headers,
      settings[source <> "_skip_ssl_verification"],
      2
    )
  rescue
    _ -> {:error, 500}
  end

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
      {:ok, status, _, _} -> {:error, status}
      {:error, :timeout} when attempts > 1 -> get(url, headers, skip, attempts - 1)
      {:error, _} -> :timeout
    end
  end
end
