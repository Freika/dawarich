defmodule Dawarich.Photos.ProviderHTTP do
  @moduledoc false
  @host ~r/\A[0-9A-Za-z._-]+\z/
  @path ~r/\A(?:\/(?!\.{1,2}(?:\/|\z))[0-9A-Za-z._~-]+)*\z/
  @max_body 32 * 1024 * 1024

  defmodule Failure do
    defexception [:reason, message: "photo source transport failure"]
  end

  def base_url?(url) when is_binary(url) do
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
          }} <- URI.new(url) do
      is_binary(host) and host =~ @host and (path || "") =~ @path and port in 1..65_535 and
        not (scheme == "http" and port == 443)
    else
      _ -> false
    end
  end

  def base_url?(_url), do: false

  def request(method, base, path, headers, body, skip, default_timeout \\ 10_000, opts \\ []) do
    if base_url?(base) do
      uri = URI.parse(base <> path)
      timeout = Application.get_env(:dawarich, :photo_source_timeout, default_timeout)
      deadline = System.monotonic_time(:millisecond) + timeout
      scheme = if uri.scheme == "https", do: :https, else: :http
      ssl = if scheme == :https, do: Dawarich.Photos.Thumbnail.ssl(skip), else: []
      headers = Enum.map(headers, fn {k, v} -> {to_string(k), to_string(v)} end)
      headers = if body, do: [{"content-type", "application/json"} | headers], else: headers

      case Mint.HTTP.connect(scheme, Keyword.get(opts, :address, uri.host), uri.port,
             hostname: uri.host,
             mode: :passive,
             protocols: [:http1],
             transport_opts: [{:timeout, remaining!(deadline)} | ssl]
           ) do
        {:ok, conn} ->
          try do
            transport = if scheme == :https, do: :ssl, else: :inet

            transport.setopts(Mint.HTTP.get_socket(conn),
              send_timeout: remaining!(deadline),
              send_timeout_close: true
            )

            target = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

            case Mint.HTTP.request(conn, String.upcase(to_string(method)), target, headers, body) do
              {:ok, conn, ref} -> receive_body(conn, ref, deadline, {nil, [], [], 0, false})
              {:error, _, reason} -> transport_error(reason)
            end
          after
            Mint.HTTP.close(conn)
          end

        {:error, reason} ->
          connect_error(reason)
      end
    else
      {:error, :invalid_url}
    end
  rescue
    e in Failure -> {:error, e.reason}
    _ -> {:error, :transport}
  end

  defp receive_body(conn, ref, deadline, state) do
    case Mint.HTTP.recv(conn, 0, remaining!(deadline)) do
      {:ok, conn, responses} ->
        remaining!(deadline)

        {status, headers, parts, size, done} =
          Enum.reduce(responses, state, fn
            {:status, ^ref, status}, {_, h, b, n, d} ->
              {status, h, b, n, d}

            {:headers, ^ref, headers}, {s, h, b, n, d} ->
              check_length!(headers)
              {s, h ++ headers, b, n, d}

            {:data, ^ref, bytes}, {s, h, b, n, d} ->
              size = n + byte_size(bytes)
              check_size!(size)
              {s, h, [bytes | b], size, d}

            {:done, ^ref}, {s, h, b, n, _} ->
              {s, h, b, n, true}

            _, acc ->
              acc
          end)

        if done,
          do: {:ok, status, headers, parts |> Enum.reverse() |> IO.iodata_to_binary()},
          else: receive_body(conn, ref, deadline, {status, headers, parts, size, done})

      {:error, _, reason, _} ->
        transport_error(reason)
    end
  end

  defp check_length!(headers) do
    for {"content-length", value} <- headers do
      case Integer.parse(value) do
        {size, ""} -> check_size!(size)
        _ -> :ok
      end
    end
  end

  defp check_size!(size) when size <= @max_body, do: :ok
  defp check_size!(_), do: raise(Failure, reason: :too_large)

  defp remaining!(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> remaining
      _ -> raise Failure, reason: :timeout
    end
  end

  defp transport_error(%Mint.TransportError{reason: :timeout}), do: {:error, :timeout}
  defp transport_error(_), do: {:error, :transport}
  defp connect_error(%Mint.TransportError{reason: :timeout}), do: {:error, :connect_timeout}
  defp connect_error(_), do: {:error, :connection}
end
