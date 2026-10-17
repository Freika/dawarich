defmodule Dawarich.Trial.WelcomeToken do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def decode(_token, nil, _now), do: {:handoff, :configuration}

  def decode(token, secret, now) when is_binary(token) and is_binary(secret) do
    with [header, payload, signature] <- String.split(token, "."),
         {:ok, header_bytes} <- Base.url_decode64(header, padding: false),
         {:ok, %{"alg" => "HS256"}} <- Jason.decode(header_bytes),
         {:ok, signature} <- Base.url_decode64(signature, padding: false),
         expected = :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload),
         true <- byte_size(signature) == byte_size(expected),
         true <- Plug.Crypto.secure_compare(signature, expected),
         {:ok, payload_bytes} <- Base.url_decode64(payload, padding: false),
         {:ok, claims} when is_map(claims) <- Jason.decode(payload_bytes),
         true <- Map.has_key?(claims, "exp"),
         true <- claims["purpose"] == "trial_welcome",
         {:ok, exp} <- integer(claims["exp"]),
         true <- exp > now,
         {:ok, not_before} <- integer(claims["nbf"]),
         true <- not_before <= now,
         {:ok, jti} <- jti(claims["jti"]) do
      {:ok, Map.put(claims, "jti", jti)}
    else
      {:handoff, _} = handoff -> handoff
      _ -> {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end

  def decode(_, _, _), do: {:error, :invalid}

  def integer(nil), do: {:ok, 0}
  def integer(value) when is_number(value), do: {:ok, trunc(value)}

  def integer(value) when is_binary(value) do
    case Regex.run(~r/\A[\x09-\x0D ]*([+-]?[0-9](?:_?[0-9])*)/, value) do
      [_, number] -> {:ok, String.to_integer(String.replace(number, "_", ""))}
      _ -> {:ok, 0}
    end
  end

  def integer(_), do: {:handoff, :claims}

  defp jti(nil), do: {:ok, ""}
  defp jti(map) when map == %{}, do: {:ok, "{}"}
  defp jti([]), do: {:ok, "[]"}

  defp jti(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: {:ok, Ruby.to_s(value)}

  defp jti(_), do: {:handoff, :claims}
end
