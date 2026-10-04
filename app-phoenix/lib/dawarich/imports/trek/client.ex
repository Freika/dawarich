defmodule Dawarich.Imports.Trek.Client do
  @moduledoc false
  defmodule Error do
    defexception [:message, :status, kind: :client]
  end

  alias Dawarich.Imports.Trek.Endpoint
  defstruct [:source, opts: []]

  def new(source, opts \\ []), do: %__MODULE__{source: source, opts: opts}

  def trips(client) do
    with {:ok, payload} <- get(client, "/api/v1/trips") do
      cond do
        not is_map(payload) ->
          error("TREK response does not contain a trip list")

        not is_list(payload["trips"]) ->
          error("TREK response does not contain trips")

        true ->
          trips = payload["trips"]
          ids = Enum.map(trips, fn trip -> if is_map(trip), do: identifier(trip["id"]) end)

          if Enum.any?(ids, &is_nil/1) or length(Enum.uniq(ids)) != length(ids),
            do: error("TREK trip list contains an invalid trip"),
            else: {:ok, trips}
      end
    end
  end

  def trip(client, id) do
    with {:ok, payload} <- get(client, "/api/v1/trips/" <> URI.encode_www_form(to_string(id))) do
      if is_map(payload), do: {:ok, payload}, else: error("TREK response does not contain a trip")
    end
  end

  defp get(client, path) do
    {uri, address} = Endpoint.resolve!(client.source.base_url <> path, client.opts)
    scheme = if uri.scheme == "https", do: :https, else: :http
    headers = [{"authorization", "Bearer " <> key!(client)}, {"accept", "application/json"}]

    case Mint.HTTP.connect(scheme, address, uri.port,
           hostname: uri.host,
           mode: :passive,
           protocols: [:http1],
           transport_opts: [timeout: 10_000]
         ) do
      {:ok, conn} ->
        try do
          target = (uri.path || "/") <> if(uri.query, do: "?" <> uri.query, else: "")

          case Mint.HTTP.request(conn, "GET", target, headers, nil) do
            {:ok, conn, ref} -> receive_body(conn, ref, nil, [])
            {:error, _, _} -> error("TREK connection failed")
          end
        after
          Mint.HTTP.close(conn)
        end

      {:error, _} ->
        error("TREK connection failed")
    end
  rescue
    e in Error -> {:error, e}
  end

  defp receive_body(conn, ref, status, body) do
    case Mint.HTTP.recv(conn, 0, 10_000) do
      {:ok, conn, responses} ->
        {status, body, done} =
          Enum.reduce(responses, {status, body, false}, fn
            {:status, ^ref, s}, {_, b, d} -> {s, b, d}
            {:data, ^ref, bytes}, {s, b, d} -> {s, [bytes | b], d}
            {:done, ^ref}, {s, b, _} -> {s, b, true}
            _, acc -> acc
          end)

        if done, do: decode(status, body), else: receive_body(conn, ref, status, body)

      {:error, _, _, _} ->
        error("TREK connection failed")
    end
  end

  defp decode(status, body) when status in 200..299 do
    case Jason.decode(body |> Enum.reverse() |> IO.iodata_to_binary()) do
      {:ok, payload} -> {:ok, payload}
      _ -> error("TREK returned invalid JSON")
    end
  end

  defp decode(status, _),
    do: {:error, %Error{message: "TREK request failed with HTTP #{status}", status: status}}

  defp identifier(id) when is_integer(id), do: Integer.to_string(id)
  defp identifier(id) when is_binary(id), do: if(String.trim(id) != "", do: id)
  defp identifier(_), do: nil

  defp key!(%{source: source, opts: opts}) do
    if opts[:encrypted?] do
      with {:ok, key} <- Dawarich.ActiveRecordEncryption.key(),
           {:ok, clear} <- Dawarich.ActiveRecordEncryption.decrypt(source.api_key, key) do
        clear
      else
        _ ->
          raise Error, message: "ActiveRecord::Encryption::Errors::Decryption", kind: :decryption
      end
    else
      source.api_key
    end
  end

  defp error(message), do: {:error, %Error{message: message}}
end
