defmodule Dawarich.SubscriptionToken do
  @moduledoc false

  def url(user, now),
    do: "#{System.get_env("MANAGER_URL")}/auth/dawarich?token=" <> generate(user, now)

  def generate(user, now, jti \\ Ecto.UUID.generate()) do
    payload =
      Jason.OrderedObject.new([
        {"user_id", user.id},
        {"email", user.email},
        {"purpose", "checkout"},
        {"jti", jti},
        {"exp", DateTime.to_unix(now) + 1800}
      ])

    input = encode(~s({"alg":"HS256"})) <> "." <> encode(Jason.encode!(payload))

    input <>
      "." <> encode(:crypto.mac(:hmac, :sha256, System.fetch_env!("JWT_SECRET_KEY"), input))
  end

  defp encode(data), do: Base.url_encode64(data, padding: false)
end
