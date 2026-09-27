defmodule DawarichWeb.LiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2, redirect: 2]

  @layout ~w(locale suggested_locale self_hosted request_path query_params flash_messages rails_csrf_token)a

  def on_mount(:default, _params, session, socket) do
    rendered = session["rails_user_id"]

    now =
      if connected?(socket),
        do: (get_connect_info(socket, :session) || %{})["rails_user_id"],
        else: rendered

    if now == rendered do
      {:cont,
       socket
       |> assign(:current_user, rendered && Dawarich.Accounts.get(rendered))
       |> assign(:now, DateTime.utc_now())
       |> assign(:navbar, [])
       |> assign(:page_title, nil)
       |> assign(for(key <- @layout, do: {key, session[Atom.to_string(key)]}))}
    else
      {:halt, redirect(socket, to: "/users/sign_in")}
    end
  end
end
