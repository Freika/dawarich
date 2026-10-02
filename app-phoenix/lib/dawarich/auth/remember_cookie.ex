defmodule Dawarich.Auth.RememberCookie do
  @moduledoc """
  Issues the signed remember cookie consumed by Rails and the legacy reader.

  Database eligibility and revocation belong to the authentication transaction;
  signing a payload does not establish that it is an accepted credential.
  """

  def sign(payload, secret, %DateTime{} = expires_at) when is_binary(secret),
    do: Dawarich.RailsCookies.sign(payload, "remember_user_token", secret, expires_at)
end
