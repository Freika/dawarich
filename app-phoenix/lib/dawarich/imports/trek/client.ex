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
    {_uri, address} = Endpoint.resolve!(client.source.base_url <> path, client.opts)
    headers = [{"authorization", "Bearer " <> key!(client)}, {"accept", "application/json"}]

    case Dawarich.Photos.ProviderHTTP.request(
           :get,
           client.source.base_url,
           path,
           headers,
           nil,
           false,
           10_000,
           address: address
         ) do
      {:ok, status, _, body} -> decode(status, body)
      {:error, _} -> error("TREK connection failed")
    end
  rescue
    e in Error -> {:error, e}
  end

  defp decode(status, body) when status in 200..299 do
    case Jason.decode(body) do
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
