defmodule Dawarich.MapMatching.Atlas.Client do
  @moduledoc """
  Atlas responses retain at most 8 MiB of body data, including error responses.
  This allows large match geometries while bounding provider-controlled memory.
  Responses exceeding the cap return transient `response_too_large` errors.

  Network requests have a 75-second monotonic deadline across connection, sending
  and receiving, in addition to the 75-second idle receive timeout. Callers may
  override these with `:request_timeout` and `:receive_timeout` (milliseconds).
  Deadline expiry returns a sanitized transient `request_timeout` error.
  """
  @max_response_bytes 8 * 1024 * 1024

  defmodule Error do
    defexception [
      :code,
      :status,
      :retry_after,
      message: "Atlas request failed",
      transient?: false
    ]
  end

  alias Dawarich.MapMatching.Atlas.Endpoint

  def health(url, opts \\ []) do
    with {:ok, payload} <- request(url, "GET", "/api/v1/health", nil, opts) do
      case payload do
        %{"data" => %{"status" => status, "capabilities" => %{"routing" => routing}}}
        when is_binary(status) and is_binary(routing) ->
          {:ok, %{status: status, routing: routing}}

        _ ->
          invalid()
      end
    end
  end

  def version(url, opts \\ []) do
    with {:ok, payload} <- request(url, "GET", "/api/v1/version", nil, opts) do
      case payload do
        %{"data" => %{"version" => version} = data} when is_binary(version) ->
          with {:ok, revision} <- revision(data["revision"]) do
            {:ok, %{version: version, revision: revision}}
          end

        _ ->
          invalid()
      end
    end
  end

  def match(url, %{shape: shape, costing: costing}, opts \\ []) do
    body =
      Jason.encode!(%{
        shape: shape,
        mode: costing,
        shape_match: "map_snap",
        format: "geojson",
        include_directions: false
      })

    with {:ok, payload} <- request(url, "POST", "/api/v1/map-match", body, opts) do
      case payload do
        %{"data" => %{"geometry" => geometry, "stats" => stats}, "meta" => provider}
        when is_map(stats) and is_map(provider) ->
          if valid_geometry?(geometry),
            do: {:ok, %{geometry: geometry, stats: stats, provider: provider}},
            else: invalid()

        _ ->
          invalid()
      end
    end
  end

  defp request(url, method, path, body, opts) do
    {uri, address} = Endpoint.resolve!(url, path)
    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :request_timeout, 75_000)
    scheme = if uri.scheme == "https", do: :https, else: :http
    headers = [{"accept", "application/json"}]
    headers = if body, do: [{"content-type", "application/json"} | headers], else: headers

    case Mint.HTTP.connect(scheme, address, uri.port,
           hostname: uri.host,
           mode: :passive,
           protocols: [:http1],
           transport_opts: [
             timeout: min(Keyword.get(opts, :connect_timeout, 5_000), remaining!(deadline))
           ]
         ) do
      {:ok, conn} ->
        try do
          transport = if scheme == :https, do: :ssl, else: :inet

          transport.setopts(Mint.HTTP.get_socket(conn),
            send_timeout: remaining!(deadline),
            send_timeout_close: true
          )

          case Mint.HTTP.request(conn, method, uri.path, headers, body) do
            {:ok, conn, ref} ->
              receive_body(
                conn,
                ref,
                Keyword.get(opts, :receive_timeout, 75_000),
                deadline,
                {nil, [], [], 0, false}
              )

            {:error, _, _} ->
              remaining!(deadline)
              connection_failed()
          end
        after
          Mint.HTTP.close(conn)
        end

      {:error, _} ->
        remaining!(deadline)
        connection_failed()
    end
  rescue
    e in Error -> {:error, e}
  end

  defp receive_body(conn, ref, idle_timeout, deadline, state) do
    budget = remaining!(deadline)

    case Mint.HTTP.recv(conn, 0, min(idle_timeout, budget)) do
      {:ok, conn, responses} ->
        remaining!(deadline)

        {status, headers, body, size, done} =
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
          do: decode(status, headers, body),
          else:
            receive_body(conn, ref, idle_timeout, deadline, {status, headers, body, size, done})

      {:error, _, %Mint.TransportError{reason: :timeout}, _} when budget <= idle_timeout ->
        error("request_timeout", nil, true)

      {:error, _, _, _} ->
        remaining!(deadline)
        connection_failed()
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

  defp check_size!(size) when size <= @max_response_bytes, do: :ok
  defp check_size!(_), do: raise(Error, code: "response_too_large", transient?: true)

  defp remaining!(deadline) do
    case deadline - System.monotonic_time(:millisecond) do
      remaining when remaining > 0 -> remaining
      _ -> raise Error, code: "request_timeout", transient?: true
    end
  end

  defp decode(status, _, body) when status in 200..299 do
    case Jason.decode(body |> Enum.reverse() |> IO.iodata_to_binary()) do
      {:ok, payload} when is_map(payload) -> {:ok, payload}
      _ -> invalid()
    end
  end

  defp decode(status, headers, _) do
    case status do
      status when status in [400, 422] -> error("invalid_input", status)
      429 -> error("capacity", status, true, retry_after(headers))
      status when status in [502, 503] -> error("unavailable", status, true)
      _ -> error("http_error", status)
    end
  end

  defp retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} ->
        case Integer.parse(String.trim(value)) do
          {seconds, ""} -> seconds
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp valid_geometry?(%{"type" => type, "coordinates" => coordinates})
       when type in ["LineString", "MultiLineString"] and is_list(coordinates),
       do: coordinates != []

  defp valid_geometry?(_), do: false
  defp revision(nil), do: {:ok, nil}

  defp revision(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: {:ok, if(String.trim(to_string(value)) == "", do: nil, else: to_string(value))}

  defp revision(_), do: invalid()
  defp invalid, do: error("provider_invalid", nil, true)
  defp connection_failed, do: error("connection_failed", nil, true)

  defp error(code, status, transient? \\ false, retry_after \\ nil),
    do:
      {:error,
       %Error{code: code, status: status, transient?: transient?, retry_after: retry_after}}
end
