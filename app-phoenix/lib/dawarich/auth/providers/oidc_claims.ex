defmodule Dawarich.Auth.Providers.OidcClaims do
  @moduledoc false
  alias Dawarich.Auth.Providers.Jwks

  def verify(token, config, nonce, context) do
    with {:ok, claims} <- signature(token, config, context),
         true <- claims["iss"] == config.issuer,
         true <- config.client_id in List.wrap(claims["aud"]),
         true <- is_number(claims["exp"]) and claims["exp"] > now(context),
         true <- is_binary(claims["sub"]) and is_number(claims["iat"]),
         true <- nonce?(claims["nonce"], nonce) do
      {:ok, claims}
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp signature(token, config, context) when is_binary(token) do
    with [header, payload, signed] <- String.split(token, "."),
         {:ok, %{"alg" => algorithm}} <- Jwks.decode(header) do
      if algorithm in ~w(HS256 HS384 HS512) do
        with secret when is_binary(secret) and secret != "" <- config.client_secret,
             {:ok, signature} <- Base.url_decode64(signed, padding: false),
             digest =
               :crypto.mac(
                 :hmac,
                 %{"HS256" => :sha256, "HS384" => :sha384, "HS512" => :sha512}[algorithm],
                 secret,
                 header <> "." <> payload
               ),
             true <- Plug.Crypto.secure_compare(signature, digest),
             {:ok, claims} when is_map(claims) <- Jwks.decode(payload) do
          {:ok, claims}
        else
          _ -> {:error, :invalid_credentials}
        end
      else
        Jwks.verify(token, config.jwks_uri, context)
      end
    else
      _ -> {:error, :invalid_credentials}
    end
  end

  defp signature(_, _, _), do: {:error, :invalid_credentials}
  defp nonce?(nil, nil), do: true

  defp nonce?(actual, expected) when is_binary(actual) and is_binary(expected),
    do: Plug.Crypto.secure_compare(actual, expected)

  defp nonce?(_, _), do: false
  defp now(context), do: Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()

  def identity(profile) do
    [first | rest] = String.split(profile["name"] || "", " ", parts: 2)

    %{
      provider: "openid_connect",
      uid: to_string(profile["sub"] || ""),
      email: profile["email"],
      email_verified: profile["email_verified"] == true,
      first_name: profile["given_name"] || first,
      last_name: profile["family_name"] || List.first(rest)
    }
  end
end
