defmodule Dawarich.Auth.Providers.Jwks do
  @moduledoc false
  alias Dawarich.TtlCache

  def request(method, url, params, headers \\ [], context \\ %{}) do
    case context[:http] do
      fun when is_function(fun, 4) -> fun.(method, url, params, headers)
      _ -> fetch(method, url, params, headers)
    end
  end

  defp fetch(method, url, params, headers) do
    headers = [{"accept", "application/json"} | headers]

    wire_headers =
      Enum.map(headers, fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    request =
      if method == :get do
        {String.to_charlist(url), wire_headers}
      else
        {String.to_charlist(url), wire_headers, ~c"application/x-www-form-urlencoded",
         URI.encode_query(params)}
      end

    options = [
      connect_timeout: 5000,
      timeout: 5000,
      autoredirect: false,
      ssl: Dawarich.Http.ssl_options()
    ]

    case :httpc.request(method, request, options, body_format: :binary) do
      {:ok, {{_, status, _}, _, body}} when status in 200..299 ->
        case Jason.decode(body) do
          {:ok, value} -> {:ok, value}
          _ -> {:error, :invalid_credentials}
        end

      {:ok, _} ->
        {:error, :invalid_credentials}

      {:error, _} ->
        {:error, :timeout}
    end
  rescue
    _ -> {:error, :provider_unavailable}
  end

  def verify(token, uri, context) when is_binary(token) and byte_size(token) <= 65536 do
    with [header, payload, signature] <- String.split(token, "."),
         {:ok, %{"alg" => algorithm} = metadata} <- decode(header),
         true <-
           algorithm in Map.get(context, :algorithms, ~w(RS256 RS384 RS512 ES256 ES384 ES512)),
         {:ok, claims} when is_map(claims) <- decode(payload),
         {:ok, bytes} <- Base.url_decode64(signature, padding: false),
         {:ok, keys} <- keys(uri, context, false),
         {:ok, keyset} <- matching(keys, metadata, uri, context),
         true <-
           Enum.any?(keyset, &valid_signature?(&1, metadata, header <> "." <> payload, bytes)) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_credentials}
    end
  rescue
    _ -> {:error, :invalid_credentials}
  end

  def verify(_, _, _), do: {:error, :invalid_credentials}

  defp matching(keys, metadata, uri, context) do
    case select(keys, metadata) do
      [] ->
        with {:ok, refreshed} <- keys(uri, context, true), do: {:ok, select(refreshed, metadata)}

      values ->
        {:ok, values}
    end
  end

  defp select(keys, metadata) do
    Enum.filter(keys, fn key ->
      (is_nil(metadata["kid"]) or key["kid"] == metadata["kid"]) and
        key["use"] in [nil, "sig"] and key["alg"] in [nil, metadata["alg"]]
    end)
  end

  defp keys(uri, context, force) when is_binary(uri) do
    :global.trans({{__MODULE__, uri}, self()}, fn ->
      now = System.monotonic_time(:second)

      cached =
        case TtlCache.lookup({__MODULE__, uri}) do
          {:ok, value} -> value
          _ -> %{keys: nil, expires: now, forced: now - 60, retry: now}
        end

      refresh = (force and now >= cached.forced + 60) or now >= cached.expires

      if refresh and (cached.keys != nil or now >= cached.retry) do
        case request(:get, uri, %{}, [], context) do
          {:ok, %{"keys" => keys}} when is_list(keys) ->
            value = %{
              keys: keys,
              expires: now + 3600,
              forced: if(force, do: now, else: cached.forced),
              retry: now
            }

            TtlCache.put({__MODULE__, uri}, value, 3_660_000)
            {:ok, keys}

          _ ->
            TtlCache.put(
              {__MODULE__, uri},
              %{cached | expires: now + 60, retry: now + 60},
              60_000
            )

            if cached.keys, do: {:ok, cached.keys}, else: {:error, :provider_unavailable}
        end
      else
        if cached.keys, do: {:ok, cached.keys}, else: {:error, :provider_unavailable}
      end
    end)
  end

  defp keys(_, _, _), do: {:error, :configuration}

  defp valid_signature?(
         %{"kty" => "RSA", "n" => n, "e" => e},
         %{"alg" => "RS" <> bits},
         input,
         signature
       ) do
    {:ok, n} = Base.url_decode64(n, padding: false)
    {:ok, e} = Base.url_decode64(e, padding: false)
    key = {:RSAPublicKey, :binary.decode_unsigned(n), :binary.decode_unsigned(e)}
    :public_key.verify(input, digest(bits), signature, key)
  rescue
    _ -> false
  end

  defp valid_signature?(
         %{"kty" => "EC", "crv" => curve, "x" => x, "y" => y},
         %{"alg" => "ES" <> bits},
         input,
         signature
       ) do
    expected = %{"256" => "P-256", "384" => "P-384", "512" => "P-521"}
    size = %{"256" => 32, "384" => 48, "512" => 66}[bits]

    with true <- curve == expected[bits],
         {:ok, x} <- Base.url_decode64(x, padding: false),
         {:ok, y} <- Base.url_decode64(y, padding: false),
         true <-
           byte_size(x) == size and byte_size(y) == size and byte_size(signature) == size * 2 do
      <<r::binary-size(^size), s::binary-size(^size)>> = signature

      der =
        :public_key.der_encode(
          :"ECDSA-Sig-Value",
          {:"ECDSA-Sig-Value", :binary.decode_unsigned(r), :binary.decode_unsigned(s)}
        )

      :crypto.verify(:ecdsa, digest(bits), input, der, [
        <<4>> <> x <> y,
        %{"256" => :secp256r1, "384" => :secp384r1, "512" => :secp521r1}[bits]
      ])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_signature?(_, _, _, _), do: false
  defp digest("256"), do: :sha256
  defp digest("384"), do: :sha384
  defp digest("512"), do: :sha512

  def decode(segment) do
    with {:ok, bytes} <- Base.url_decode64(segment, padding: false), do: Jason.decode(bytes)
  end
end
