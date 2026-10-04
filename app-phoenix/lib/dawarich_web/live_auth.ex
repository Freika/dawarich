defmodule DawarichWeb.LiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3, assign_new: 3]

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_info: 2, put_flash: 3, redirect: 2]

  @layout ~w(locale suggested_locale self_hosted request_path query_params rails_csrf_token base_url)a

  def on_mount(:default, _params, session, socket) do
    rendered = session["rails_user_id"]

    connected_user =
      if connected?(socket),
        do: (get_connect_info(socket, :session) || %{})["rails_user_id"],
        else: rendered

    if connected_user == rendered do
      {:cont,
       socket
       |> assign_new(:current_user, fn -> rendered && Dawarich.Accounts.get(rendered) end)
       |> assign_new(:now, &DateTime.utc_now/0)
       |> assign(:navbar, nil)
       |> assign(:page_title, nil)
       |> assign(:flash_messages, [])
       |> assign(for(key <- @layout, do: {key, session[Atom.to_string(key)]}))
       |> rails_flash(session["flash_messages"] || [])
       |> attach_hook(:rails_user, :handle_event, &still_signed_in/3)
       |> DawarichWeb.NavbarHooks.attach()}
    else
      {:halt, redirect(socket, to: "/users/sign_in")}
    end
  end

  defp rails_flash(socket, messages) do
    if connected?(socket),
      do: socket,
      else:
        Enum.reduce(messages, socket, fn {type, message}, acc ->
          put_flash(acc, to_string(type), message)
        end)
  end

  defp still_signed_in(_event, _params, %{assigns: %{current_user: user}} = socket) do
    if Dawarich.Accounts.get(user.id),
      do: {:cont, socket},
      else: {:halt, redirect(socket, to: socket.assigns.request_path)}
  end
end
