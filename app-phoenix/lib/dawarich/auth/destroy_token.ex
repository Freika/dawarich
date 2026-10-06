defmodule Dawarich.Auth.DestroyToken do
  @moduledoc false
  alias Dawarich.Auth.Api.ChallengeToken
  alias Dawarich.{RailsCache.Wire, Redis}
  @ttl 3600

  def issue(id, context) do
    with {:ok, secret} <- ChallengeToken.secret(context) do
      now = epoch(context)

      payload = %Jason.OrderedObject{
        values: [
          {"user_id", id},
          {"purpose", "account_destroy"},
          {"jti", Ecto.UUID.generate()},
          {"iat", now},
          {"exp", now + @ttl}
        ]
      }

      input = encode(%Jason.OrderedObject{values: [{"alg", "HS256"}]}) <> "." <> encode(payload)

      {:ok,
       input <>
         "." <> Base.url_encode64(:crypto.mac(:hmac, :sha256, secret, input), padding: false)}
    else
      _ -> {:error, :secret}
    end
  end

  def verify(token, context) when is_binary(token) and byte_size(token) <= 16_384 do
    with {:ok, secret} <- ChallengeToken.secret(context),
         [header, payload, signed] <- String.split(token, "."),
         {:ok, signature} <- Base.url_decode64(signed, padding: false),
         true <- byte_size(signature) == 32,
         true <-
           Plug.Crypto.secure_compare(
             signature,
             :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload)
           ),
         {:ok, %{"alg" => "HS256"}} <- decode(header),
         {:ok, claims} <- decode(payload),
         true <- valid?(claims, context) do
      case command(["GET", key(claims["jti"])], context) do
        {:ok, nil} -> {:ok, claims}
        {:ok, _} -> {:error, :replayed}
        _ -> {:error, :cache}
      end
    else
      _ -> {:error, :invalid_token}
    end
  end

  def verify(_, _), do: {:error, :invalid_token}

  def consume(jti, context) do
    bytes = Wire.encode_boolean(true, expires_at: epoch(context) + @ttl)

    case command(["SET", key(jti), bytes, "NX", "PX", Integer.to_string(@ttl * 1000)], context) do
      {:ok, "OK"} -> true
      _ -> false
    end
  end

  defp valid?(claims, context) do
    now = epoch(context)

    is_integer(claims["user_id"]) and claims["user_id"] > 0 and
      claims["purpose"] == "account_destroy" and
      is_binary(claims["jti"]) and String.trim(claims["jti"]) != "" and
      is_integer(claims["exp"]) and claims["exp"] > now and
      (is_nil(claims["iat"]) or (is_integer(claims["iat"]) and now - claims["iat"] <= @ttl))
  end

  defp encode(value), do: Jason.encode!(value) |> Base.url_encode64(padding: false)

  defp decode(value) do
    with {:ok, bytes} <- Base.url_decode64(value, padding: false), do: Jason.decode(bytes)
  end

  defp key(jti), do: "account_destroy:consumed:" <> jti
  defp command(args, context), do: Map.get(context, :cache_command, &Redis.cache_command/1).(args)
  defp epoch(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
end
