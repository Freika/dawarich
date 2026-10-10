defmodule Dawarich.SubscriptionToken do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def url(user, now, checkout \\ []),
    do:
      "#{System.get_env("MANAGER_URL")}/auth/dawarich?token=" <>
        generate(user, now, Ecto.UUID.generate(), checkout)

  def generate(user, now, jti \\ Ecto.UUID.generate()), do: generate(user, now, jti, [])

  def generate(user, now, jti, opts) do
    options =
      for key <- [:plan, :interval, :variant],
          value = Keyword.get(opts, key),
          Ruby.present?(value),
          do: {Atom.to_string(key), value}

    payload =
      Jason.OrderedObject.new(
        [
          {"user_id", user.id},
          {"email", user.email},
          {"purpose", "checkout"},
          {"jti", jti},
          {"exp", DateTime.to_unix(now) + 1800}
        ] ++ options
      )

    input = encode(~s({"alg":"HS256"})) <> "." <> encode(Jason.encode!(payload))

    input <>
      "." <> encode(:crypto.mac(:hmac, :sha256, System.fetch_env!("JWT_SECRET_KEY"), input))
  end

  defp encode(data), do: Base.url_encode64(data, padding: false)
end
