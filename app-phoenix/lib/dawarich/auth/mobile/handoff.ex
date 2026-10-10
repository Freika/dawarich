defmodule Dawarich.Auth.Mobile.Handoff do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Token

  def secret(context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)
    value = env["AUTH_JWT_SECRET_KEY"]

    if Token.blank?(value),
      do: Map.get_lazy(context, :rails_secret, &Dawarich.RailsSecret.fetch/0),
      else: value
  end

  def redirect(user, client, context) when client in ["ios", "android"] do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
    header = Base.url_encode64(~s({"alg":"HS256"}), padding: false)

    payload =
      Jason.encode!(Jason.OrderedObject.new([{"api_key", user.api_key}, {"exp", now + 300}]))
      |> Base.url_encode64(padding: false)

    input = header <> "." <> payload

    signature =
      :crypto.mac(:hmac, :sha256, secret(context), input) |> Base.url_encode64(padding: false)

    {:ok, "/auth/ios/success?" <> URI.encode_query(%{"token" => input <> "." <> signature})}
  end
end
