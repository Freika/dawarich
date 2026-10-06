defmodule Dawarich.Auth.SessionCookie do
  @moduledoc false
  alias Dawarich.RailsCookies
  alias Dawarich.Auth.Otp.Pending
  alias DawarichWeb.{RailsCsrf, RailsSession}

  @name "_dawarich_session"
  @login_drop ~w(session_id _csrf_token user_return_to warden.user.user.key warden.user.user.session)

  def for_form(session, secret) do
    session = default(session, "session_id", &session_id/0)
    session = default(session, "_csrf_token", &RailsCsrf.new_token/0)
    encode(session, secret)
  end

  def for_login(session, user, notice, secret) do
    session =
      session
      |> Map.drop(@login_drop)
      |> Map.reject(fn {key, _value} -> String.starts_with?(key, "devise.") end)
      |> Map.put("session_id", session_id())
      |> Map.put("warden.user.user.key", [[user.id], binary_part(user.encrypted_password, 0, 29)])
      |> Map.put("flash", flash(notice))

    encode(session, secret)
  end

  def for_otp_login(session, user, notice, secret) do
    session =
      session
      |> Pending.clear()
      |> Map.drop(~w(session_id user_return_to warden.user.user.key))
      |> Map.reject(fn {key, _value} -> String.starts_with?(key, "devise.") end)
      |> Map.put("session_id", session_id())
      |> Map.put("warden.user.user.key", [[user.id], binary_part(user.encrypted_password, 0, 29)])
      |> Map.put("flash", flash(notice))

    encode(session, secret)
  end

  def for_logout(notice, secret) do
    encode(%{"session_id" => session_id(), "flash" => flash(notice)}, secret)
  end

  def for_account_link(session, user, kind, notice, secret) when kind in [:sign_in, :link_only] do
    session = Map.drop(session, ~w(pending_oauth_link pending_oauth_link_attempts))

    session =
      if kind == :sign_in do
        session
        |> Map.reject(fn {key, _} -> String.starts_with?(key, "devise.") end)
        |> Map.put("session_id", session_id())
        |> Map.put("warden.user.user.key", [
          [user.id],
          binary_part(user.encrypted_password, 0, 29)
        ])
      else
        session
      end

    session |> Map.put("flash", flash(notice)) |> encode(secret)
  end

  def for_account_update(session, user, notice, secret) do
    session =
      session
      |> Map.reject(fn {key, _} -> String.starts_with?(key, "devise.") end)
      |> Map.put("warden.user.user.key", [[user.id], binary_part(user.encrypted_password, 0, 29)])
      |> Map.put("flash", flash(notice))

    encode(session, secret)
  end

  def for_restore(session, user, secret) do
    session =
      session
      |> Map.drop(@login_drop -- ["user_return_to", "_csrf_token"])
      |> Map.put("session_id", session_id())
      |> Map.put("warden.user.user.key", [[user.id], binary_part(user.encrypted_password, 0, 29)])

    encode(session, secret)
  end

  defp flash(notice), do: %{"discard" => [], "flashes" => %{"notice" => notice}}
  defp session_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp default(session, key, fun) do
    case Map.get(session, key) do
      value when value in [nil, false] -> Map.put(session, key, fun.())
      _ -> session
    end
  end

  defp encode(session, secret) do
    cookie = RailsCookies.encrypt(session, @name, secret)
    size = byte_size(@name) + byte_size(URI.decode_www_form(cookie))
    if size > 4096, do: raise(RailsSession.Overflow, size: size)
    {session, cookie}
  end
end
