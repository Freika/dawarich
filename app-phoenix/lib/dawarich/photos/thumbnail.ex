defmodule Dawarich.Photos.Thumbnail do
  @moduledoc false

  alias Dawarich.Http
  alias Dawarich.Photos.ProviderHTTP
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @id ~r/\A[0-9A-Za-z_-]{1,128}\z/
  @key ~r/\A[!-~]+\z/
  @statuses [400, 401, 404, 405, 408, 409, 410, 413, 414, 415, 422, 429, 500, 501, 502, 503, 504]
  @environment ~w(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY SSL_CERT_FILE SSL_CERT_DIR)

  defdelegate fetch(settings, source, id, user), to: Dawarich.Photos.ThumbnailClosure

  def configured?(settings), do: pair?(settings, "immich") or pair?(settings, "photoprism")

  def fetch(_settings, "photoprism", _id),
    do: {:replay, "PhotoPrism preview token is in the Rails cache"}

  def fetch(settings, "immich", id) do
    with :ok <-
           check(
             Enum.all?(@environment, &(System.get_env(&1, "") == "")),
             "proxy or CA environment Phoenix does not model"
           ),
         :ok <- check(pair?(settings, "immich"), "Immich is not configured"),
         :ok <- check(is_binary(id) and id =~ @id, "photo id shape"),
         :ok <- check(ProviderHTTP.base_url?(settings["immich_url"]), "photo source URL shape"),
         :ok <- check(key?(settings["immich_api_key"]), "Immich API key shape") do
      request(
        settings["immich_url"],
        "/api/assets/" <> id <> "/thumbnail?size=preview",
        headers(settings["immich_api_key"]),
        settings["immich_skip_ssl_verification"],
        2
      )
      |> classify()
    end
  end

  @doc false
  def ssl(skip) when skip in [nil, false], do: Http.ssl_options()
  def ssl(_skip), do: [verify: :verify_none]

  defp pair?(settings, source),
    do:
      Ruby.present?(settings[source <> "_url"]) and Ruby.present?(settings[source <> "_api_key"])

  defp check(true, _reason), do: :ok
  defp check(false, reason), do: {:replay, reason}

  defp key?(key), do: is_binary(key) and key =~ @key

  defp headers(key) do
    [
      {~c"accept", ~c"application/octet-stream"},
      {~c"x-api-key", String.to_charlist(key)},
      {~c"connection", ~c"close"}
    ]
  end

  defp request(base, path, headers, skip, attempts) do
    case ProviderHTTP.request(:get, base, path, headers, nil, skip, 60_000) do
      {:error, :timeout} when attempts > 1 -> request(base, path, headers, skip, attempts - 1)
      {:ok, status, headers, body} -> {:ok, {status, headers, body}}
      {:error, :too_large} -> :too_large
      error -> error
    end
  end

  defp classify({:ok, {status, headers, body}}) do
    cond do
      encoded?(headers) -> {:replay, "photo source response is content-encoded"}
      status in 200..299 and body != "" -> {:ok, body}
      status in @statuses -> {:error, status}
      true -> {:replay, "photo source answered #{status}"}
    end
  end

  defp classify(:too_large), do: {:replay, "photo source body exceeds the size cap"}
  defp classify({:error, :timeout}), do: :timeout

  defp classify({:error, :connect_timeout}), do: :timeout
  defp classify({:error, :connection}), do: {:replay, "photo source unreachable"}

  defp classify({:error, _reason}), do: {:replay, "photo source transport failure"}

  defp encoded?(headers) do
    Enum.any?(headers, fn {name, value} ->
      String.downcase(to_string(name)) == "content-encoding" and
        String.downcase(to_string(value)) != "identity"
    end)
  end
end
