defmodule Dawarich.Photos.Thumbnail do
  @moduledoc false

  alias Dawarich.Http
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @id ~r/\A[0-9A-Za-z_-]{1,128}\z/
  @host ~r/\A[0-9A-Za-z._-]+\z/
  @path ~r/\A(?:\/(?!\.{1,2}(?:\/|\z))[0-9A-Za-z._~-]+)*\z/
  @key ~r/\A[!-~]+\z/
  @statuses [400, 401, 404, 405, 408, 409, 410, 413, 414, 415, 422, 429, 500, 501, 502, 503, 504]
  @environment ~w(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY SSL_CERT_FILE SSL_CERT_DIR)
  @max_body 32 * 1024 * 1024

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
         :ok <- check(url?(settings["immich_url"]), "photo source URL shape"),
         :ok <- check(key?(settings["immich_api_key"]), "Immich API key shape") do
      (settings["immich_url"] <> "/api/assets/" <> id <> "/thumbnail?size=preview")
      |> request(
        headers(settings["immich_api_key"]),
        ssl(settings["immich_skip_ssl_verification"]),
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

  defp url?(url) when is_binary(url) do
    with true <- String.starts_with?(url, ["http://", "https://"]),
         {:ok,
          %URI{
            scheme: scheme,
            host: host,
            port: port,
            path: path,
            userinfo: nil,
            query: nil,
            fragment: nil
          }} <-
           URI.new(url) do
      is_binary(host) and host =~ @host and (path || "") =~ @path and port in 1..65_535 and
        not (scheme == "http" and port == 443)
    else
      _ -> false
    end
  end

  defp url?(_url), do: false

  defp key?(key), do: is_binary(key) and key =~ @key

  defp headers(key) do
    [
      {~c"accept", ~c"application/octet-stream"},
      {~c"x-api-key", String.to_charlist(key)},
      {~c"connection", ~c"close"}
    ]
  end

  defp request(url, headers, ssl, attempts) do
    timeout = Application.get_env(:dawarich, :photo_source_timeout, 60_000)
    options = [timeout: timeout, connect_timeout: timeout, autoredirect: false, ssl: ssl]
    streaming = [sync: false, stream: {:self, :once}, body_format: :binary]

    result =
      with {:ok, ref} <-
             :httpc.request(:get, {String.to_charlist(url), headers}, options, streaming),
           do: receive_response(ref, nil)

    case result do
      {:error, :timeout} when attempts > 1 -> request(url, headers, ssl, attempts - 1)
      result -> result
    end
  end

  defp receive_response(ref, stream) do
    receive do
      {:http, {^ref, :stream_start, headers, handler}} ->
        :httpc.stream_next(handler)
        receive_response(ref, %{headers: headers, handler: handler, parts: [], size: 0})

      {:http, {^ref, :stream, part}} ->
        size = stream.size + byte_size(part)

        if size > @max_body do
          :httpc.cancel_request(ref)
          :too_large
        else
          :httpc.stream_next(stream.handler)
          receive_response(ref, %{stream | parts: [stream.parts | part], size: size})
        end

      {:http, {^ref, :stream_end, _headers}} ->
        {:ok, {200, stream.headers, IO.iodata_to_binary(stream.parts)}}

      {:http, {^ref, {{_version, status, _reason}, headers, body}}} ->
        if byte_size(body) > @max_body, do: :too_large, else: {:ok, {status, headers, body}}

      {:http, {^ref, {:error, reason}}} ->
        {:error, reason}
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

  defp classify({:error, {:failed_connect, details}}) do
    if Enum.any?(details, &match?({_family, _options, :timeout}, &1)),
      do: :timeout,
      else: {:replay, "photo source unreachable"}
  end

  defp classify({:error, _reason}), do: {:replay, "photo source transport failure"}

  defp encoded?(headers) do
    Enum.any?(headers, fn {name, value} ->
      String.downcase(to_string(name)) == "content-encoding" and
        String.downcase(to_string(value)) != "identity"
    end)
  end
end
