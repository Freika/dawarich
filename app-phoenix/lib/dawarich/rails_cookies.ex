defmodule Dawarich.RailsCookies do
  @moduledoc false

  @encrypted_salt "authenticated encrypted cookie"
  @signed_salt "signed cookie"

  def decrypt(value, name, secret, now) do
    with [data, iv, tag] <- value |> URI.decode_www_form() |> String.split("--"),
         {:ok, data} <- Base.decode64(data),
         {:ok, iv} <- Base.decode64(iv),
         {:ok, tag} <- Base.decode64(tag),
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

  defp key(secret, salt, length) do
    id = {__MODULE__, :crypto.hash(:sha256, secret), salt, length}

    case :persistent_term.get(id, nil) do
      nil ->
        key =
          Plug.Crypto.KeyGenerator.generate(secret, salt,
            iterations: 1000,
            length: length,
            digest: :sha256
          )

        :persistent_term.put(id, key)
        key

      key ->
        key
    end
  end
end
