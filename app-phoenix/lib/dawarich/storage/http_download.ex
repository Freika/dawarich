defmodule Dawarich.Storage.HttpDownload do
  @moduledoc false
  alias Dawarich.Imports.SecureFileDownloader.TimeoutError

  def stream!(url, sink) do
    uri = URI.parse(url)
    scheme = scheme!(uri)
    options = [timeout: 300_000]
    options = if scheme == :https, do: options ++ Dawarich.Http.ssl_options(), else: options

    conn =
      case Mint.HTTP.connect(scheme, uri.host, uri.port,
             mode: :passive,
             protocols: [:http1],
             transport_opts: options
           ) do
        {:ok, conn} -> Mint.HTTP.put_log(conn, false)
        {:error, reason} -> transport_error!(reason)
      end

    try do
      path = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

      case Mint.HTTP.request(conn, "GET", path, [], nil) do
        {:ok, conn, ref} -> receive_body!(conn, ref, sink)
        {:error, _, reason} -> transport_error!(reason)
      end
    after
      Mint.HTTP.close(conn)
    end
  end

  defp receive_body!(conn, ref, sink) do
    case Mint.HTTP.recv(conn, 0, 300_000) do
      {:ok, conn, responses} ->
        if consume!(responses, ref, sink), do: :ok, else: receive_body!(conn, ref, sink)

      {:error, _conn, reason, responses} ->
        if consume!(responses, ref, sink), do: :ok, else: transport_error!(reason)
    end
  end

  defp consume!(responses, ref, sink) do
    Enum.reduce(responses, false, fn
      {:status, ^ref, 200}, done ->
        done

      {:status, ^ref, status}, done when status in 100..199 and status != 101 ->
        done

      {:status, ^ref, status}, _ ->
        raise "Import download HTTP #{status}"

      {:data, ^ref, chunk}, done ->
        sink.(chunk)
        done

      {:done, ^ref}, _ ->
        true

      _, done ->
        done
    end)
  end

  defp transport_error!(%{reason: :timeout}), do: raise(TimeoutError)
  defp transport_error!(_), do: raise("Import download transport failed")

  defp scheme!(%URI{scheme: "https", host: host, userinfo: nil, fragment: nil})
       when is_binary(host) and host != "",
       do: :https

  defp scheme!(%URI{scheme: "http", host: host, userinfo: nil, fragment: nil})
       when is_binary(host) and host != "",
       do: :http

  defp scheme!(_), do: raise(ArgumentError, "Invalid import storage URL")
end
