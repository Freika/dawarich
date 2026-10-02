defmodule Dawarich.RailsCookies do
  @moduledoc false

  alias Dawarich.RailsMessages
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @encrypted_salt "authenticated encrypted cookie"
  @signed_salt "signed cookie"

  def decrypt(value, name, secret, now) do
    with [data, iv, tag] <- value |> URI.decode_www_form() |> String.split("--"),
         {:ok, data} <- Base.decode64(data),
         {:ok, <<_::binary-size(12)>> = iv} <- Base.decode64(iv),
         {:ok, <<_::binary-size(16)>> = tag} <- Base.decode64(tag),
         plain when is_binary(plain) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key(secret, @encrypted_salt, 32),
             iv,
             data,
             "",
             tag,
             false
           ) do
      unwrap(plain, name, now)
    else
      _ -> :error
    end
  rescue
    _ in [ArgumentError, ErlangError] -> :error
  end

  def encrypt(value, name, secret, expires_at \\ nil) do
    exp = if expires_at, do: RailsMessages.iso8601_ms(expires_at)
    envelope = envelope(value, name, exp)
    iv = :crypto.strong_rand_bytes(12)
    key = key(secret, @encrypted_salt, 32)
    {data, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, envelope, "", true)
    [data, iv, tag] |> Enum.map_join("--", &Base.encode64/1) |> URI.encode_www_form()
  end

  def sign(value, name, secret, %DateTime{} = expires_at) do
    exp = expires_at |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
    data = value |> envelope(name, exp) |> Base.encode64()
    URI.encode_www_form(data <> "--" <> hmac(secret, data))
  end

  def verify(value, name, secret, now) do
    with [data, digest] <- value |> URI.decode_www_form() |> String.split("--"),
         true <- Plug.Crypto.secure_compare(digest, hmac(secret, data)),
         {:ok, plain} <- Base.decode64(data) do
      unwrap(plain, name, now)
    else
      _ -> :error
    end
  rescue
    _ in [ArgumentError, ErlangError] -> :error
  end

  defp envelope(value, name, exp) do
    json = value |> Ruby.json() |> IO.iodata_to_binary()
    meta = Jason.OrderedObject.new(message: Base.encode64(json), exp: exp, pur: "cookie." <> name)
    Jason.encode!(%{"_rails" => meta})
  end

  defp unwrap(plain, name, now) do
    with {:ok, %{"_rails" => %{"message" => message, "pur" => purpose} = meta}} <-
           Jason.decode(plain),
         true <- purpose == "cookie." <> name,
         false <- expired?(meta["exp"], now),
         {:ok, json} <- Base.decode64(message),
         {:ok, value} <- Jason.decode(json) do
      {:ok, value}
    else
      _ -> :error
    end
  end

  defp expired?(nil, _now), do: false

  defp expired?(expiry, now) do
    case DateTime.from_iso8601(expiry) do
      {:ok, at, _offset} -> DateTime.compare(now, at) != :lt
      _ -> true
    end
  end

  defp hmac(secret, data),
    do:
      :hmac
      |> :crypto.mac(:sha, key(secret, @signed_salt, 64), data)
      |> Base.encode16(case: :lower)

  defp key(secret, salt, length), do: RailsMessages.key(secret, salt, 1000, length)
end
