defmodule DawarichWeb.AuthNavigation do
  @moduledoc false
  alias Dawarich.Auth.{Admission, RegistrationPolicy}

  def sign_in(conn, opts, fallback) do
    with true <- Keyword.get(opts, :native, false),
         {:ok, params} <- Admission.form(conn.query_string, "", ~w(locale invitation_token)),
         true <- valid?(params) do
      conn |> invitation_session(params) |> DawarichWeb.AuthResponse.form("", nil, 200)
    else
      _ -> fallback.(conn, opts)
    end
  end

  def credentials(conn, raw, opts) do
    if Keyword.get(opts, :native, false) do
      with {:ok, params} <-
             Admission.form(
               raw,
               conn.query_string,
               ~w(authenticity_token user[email] user[password] user[remember_me] commit utf8 _method invitation_token),
               checkbox_pairs: %{"user[remember_me]" => ["0", "1"]}
             ),
           true <- valid?(params) do
        {:ok, params, invitation_session(conn, params)}
      else
        _ -> :error
      end
    else
      case Admission.form(raw, conn.query_string) do
        {:ok, params} -> {:ok, params, conn}
        other -> other
      end
    end
  end

  def invitation(session), do: RegistrationPolicy.invitation(session["invitation_token"], %{})

  def return_to(session, fallback) do
    case invitation(session) do
      %{acceptable: true, token: token} -> "/invitations/" <> URI.encode_www_form(token)
      _ -> fallback
    end
  end

  def locale_query?(query) do
    case Admission.form(query, "", ~w(locale)) do
      {:ok, %{"locale" => locale}} -> locale in Dawarich.Localization.locales()
      _ -> false
    end
  end

  defp valid?(params) do
    (not Map.has_key?(params, "locale") or params["locale"] in Dawarich.Localization.locales()) and
      (not Map.has_key?(params, "invitation_token") or
         byte_size(params["invitation_token"]) <= 4096)
  end

  defp invitation_session(conn, %{"invitation_token" => token}),
    do:
      Plug.Conn.assign(
        conn,
        :rails_session,
        Map.put(conn.assigns.rails_session, "invitation_token", token)
      )

  defp invitation_session(conn, _params), do: conn
end
