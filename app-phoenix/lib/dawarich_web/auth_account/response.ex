defmodule DawarichWeb.AuthAccount.Response do
  @moduledoc false
  import Plug.Conn
  alias Dawarich.{Accounts, RailsSecret}
  alias Dawarich.Auth.SessionCookie

  alias DawarichWeb.{AuthCookie, AuthMessages, RailsHeaders, RequestURL}

  def updated(conn, user, context \\ %{}) do
    user = %{
      conn.assigns.current_user
      | email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        encrypted_password: user.encrypted_password
    }

    conn = current(conn, user)

    conn
    |> AuthCookie.session(
      SessionCookie.for_account_update(
        conn.assigns.rails_session,
        user,
        AuthMessages.notice(conn, "devise.registrations.updated"),
        secret(context)
      )
    )
    |> headers()
    |> put_resp_header("location", RequestURL.base(conn) <> "/")
    |> send_resp(303, "")
    |> halt()
  end

  def form(conn, actor, render, context \\ %{}) do
    conn = current(conn, Accounts.get(actor.id))

    form = %{
      "email" => if(byte_size(render.email || "") <= 254, do: render.email),
      "errors" =>
        Enum.map(render.errors, fn {field, kind, bindings} ->
          [Atom.to_string(field), Atom.to_string(kind), bindings]
        end)
    }

    conn
    |> AuthCookie.session(
      SessionCookie.for_form(
        Map.put(conn.assigns.rails_session, "dawarich.account_form", form),
        secret(context)
      )
    )
    |> headers()
    |> put_resp_header("location", RequestURL.base(conn) <> "/users/edit")
    |> send_resp(303, "")
    |> halt()
  end

  def errors(%{"errors" => errors}) when is_list(errors),
    do:
      for(
        [field, kind, bindings] <- errors,
        do: {String.to_existing_atom(field), String.to_existing_atom(kind), bindings}
      )

  def errors(_form), do: []

  defp current(conn, user),
    do: conn |> assign(:current_user, user) |> put_private(:dawarich_rails_user, user)

  defp secret(context), do: Map.get_lazy(context, :secret, &RailsSecret.fetch/0)

  defp headers(conn),
    do:
      conn |> RailsHeaders.call([]) |> put_resp_header("x-dawarich-auth-owner", "native-account")
end
