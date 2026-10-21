defmodule DawarichWeb.AuthMessages do
  @moduledoc false
  def notice(conn, key, bindings \\ %{}) do
    locale =
      DawarichWeb.Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

    {:ok, text} = Dawarich.I18n.t(locale, key, bindings)
    text
  end

  def invalid(conn) do
    key = authentication_key(conn)
    message = notice(conn, "devise.failure.invalid", %{"authentication_keys" => key})

    if String.starts_with?(message, key) do
      {first, rest} = String.split_at(message, 1)
      String.upcase(first) <> rest
    else
      message
    end
  end

  def authentication_key(conn) do
    locale =
      DawarichWeb.Locale.resolve(nil, conn.assigns.current_user, conn.assigns.rails_session)

    key =
      case Dawarich.I18n.t(locale, "activerecord.attributes.user.email") do
        {:ok, key} -> key
        _ -> "Email"
      end

    {first, rest} = String.split_at(key, 1)
    String.downcase(first) <> rest
  end
end
