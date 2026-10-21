defmodule Dawarich.Auth.Trackable do
  @moduledoc """
  Prepares Devise-compatible sign-in history changes for an accepted authentication.

  Call under the authentication transaction's user lock. Ordinary session reads
  and rejected credentials must not apply these changes.
  """

  def changes(user, %DateTime{} = now, ip) when is_binary(ip) do
    %{
      sign_in_count: (user.sign_in_count || 0) + 1,
      current_sign_in_at: now,
      last_sign_in_at: user.current_sign_in_at || now,
      current_sign_in_ip: ip,
      last_sign_in_ip: user.current_sign_in_ip || ip
    }
  end
end
