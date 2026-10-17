defmodule Dawarich.Trial.WelcomeSession do
  @moduledoc false
  alias Dawarich.Auth.SessionCookie
  alias Dawarich.{I18n, RailsCookies}
  alias DawarichWeb.RailsSession

  def cookie(conn, user, notice, secret, true) do
    {session, _} = SessionCookie.for_login(conn.assigns.rails_session, user, notice, secret)

    session =
      if Map.has_key?(conn.assigns.rails_session, "user_return_to"),
        do: Map.put(session, "user_return_to", conn.assigns.rails_session["user_return_to"]),
        else: session

    SessionCookie.for_account_update(session, user, notice, secret)
  end

  def cookie(conn, _user, notice, secret, false),
    do: flash_cookie(conn, %{"notice" => notice}, secret)

  def result(conn, path, key, locale, context) do
    {:ok, message} = I18n.t(locale, "controllers.trial.welcome." <> key)
    flash = %{"alert" => message}

    {:ok,
     %{result: %{path: path, flash: flash, cookie: flash_cookie(conn, flash, context.secret)}}}
  end

  defp flash_cookie(conn, flash, secret) do
    changes = %{"flash" => %{"discard" => [], "flashes" => flash}}

    case RailsSession.rewrite(conn.cookies["_dawarich_session"], changes, secret) do
      {:ok, cookie} ->
        {:ok, session} =
          RailsCookies.decrypt(cookie, "_dawarich_session", secret, DateTime.utc_now())

        {session, cookie}

      :unchanged ->
        nil
    end
  end
end
