defmodule DawarichWeb.LiveAuth do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3, assign_new: 3]
  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2, put_flash: 3, redirect: 2]

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
       |> assign(:now, DateTime.utc_now())
       |> assign(:navbar, [])
       |> assign(:page_title, nil)
       |> assign(:flash_messages, [])
       |> assign(for(key <- @layout, do: {key, session[Atom.to_string(key)]}))
       |> rails_flash(session["flash_messages"] || [])}
    else
      {:halt, redirect(socket, to: "/users/sign_in")}
    end
  end

  defp rails_flash(socket, messages),
    do:
      Enum.reduce(messages, socket, fn {type, message}, acc ->
        put_flash(acc, to_string(type), message)
      end)
end
