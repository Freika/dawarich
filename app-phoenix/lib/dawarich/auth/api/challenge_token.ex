defmodule Dawarich.Auth.Api.ChallengeToken do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.RailsSecret
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def secret(context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    explicit = env["JWT_SECRET_KEY"]

    value =
      if Token.blank?(explicit),
        do: Map.get_lazy(context, :rails_secret, &RailsSecret.fetch/0),
        else: explicit

    if is_binary(value) and value != "", do: {:ok, value}, else: {:replay, :secret}
  end

  def issue(user_id, context) when is_integer(user_id) do
    with {:ok, secret} <- secret(context) do
      now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
      jti = Map.get(context, :jti, &Ecto.UUID.generate/0).()

      claims =
        {:object,
         [
           {"user_id", user_id},
           {"purpose", "otp_challenge"},
           {"jti", jti},
           {"iat", now},
           {"exp", now + 300}
         ]}

      input = encode({:object, [{"alg", "HS256"}]}) <> "." <> encode(claims)
      signature = :crypto.mac(:hmac, :sha256, secret, input) |> Base.url_encode64(padding: false)
      {:ok, input <> "." <> signature}
    end
  end

  def verify(token, context) when is_binary(token) and byte_size(token) <= 16_384 do
    with {:ok, secret} <- secret(context),
         [header, payload, signed] <- String.split(token, "."),
         {:ok, signature} <- decode_bytes(signed),
         true <- byte_size(signature) == 32,
         digest = :crypto.mac(:hmac, :sha256, secret, header <> "." <> payload),
         true <- Plug.Crypto.secure_compare(signature, digest),
         {:ok, [{"alg", "HS256"}]} <- object(header),
         {:ok, pairs} <- object(payload),
         true <- Enum.sort(Enum.map(pairs, &elem(&1, 0))) == ~w(exp iat jti purpose user_id),
         claims = Map.new(pairs),
         true <- normal?(claims, context) do
      {:ok, claims}
    else
      _ -> {:replay, :token}
    end
  rescue
    _ in [ArgumentError, Jason.DecodeError] -> {:replay, :token}
  end

  def verify(_, _), do: {:replay, :token}

  defp decode_bytes(segment) do
    with {:ok, bytes} <- Base.url_decode64(segment, padding: false),
         true <- Base.url_encode64(bytes, padding: false) == segment do
      {:ok, bytes}
    else
      _ -> :invalid
    end
  end

  defp object(segment) do
    with {:ok, bytes} <- decode_bytes(segment),
         {:ok, %Jason.OrderedObject{values: pairs}} <-
           Jason.decode(bytes, objects: :ordered_objects) do
      {:ok, pairs}
    else
      _ -> :invalid
    end
  end

  defp normal?(claims, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
    id = claims["user_id"]
    iat = claims["iat"]
    exp = claims["exp"]
    jti = claims["jti"]

    is_integer(id) and id in 1..9_223_372_036_854_775_807 and is_integer(iat) and iat > 0 and
      is_integer(exp) and
      exp > now and now - iat <= 300 and claims["purpose"] == "otp_challenge" and
      is_binary(jti) and
      Regex.match?(
        ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/,
        jti
      )
  end

  defp encode(term),
    do: term |> Ruby.json() |> IO.iodata_to_binary() |> Base.url_encode64(padding: false)
end
