defmodule DawarichWeb.PublicMapAuth do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]

  import Phoenix.LiveView,
    only: [attach_hook: 4, connected?: 1, get_connect_info: 2, push_event: 3]

  alias Dawarich.Maps.Dependencies.Public
  alias DawarichWeb.{RailsAuth, SharedLinkCookie}

  @layout ~w(locale suggested_locale self_hosted request_path query_params base_url notification_session)a
  def live_session(conn) do
    user = conn.assigns[:current_user]

    capability = %{
      id: conn.path_params["id"],
      proof: SharedLinkCookie.proofs(conn)[conn.path_params["id"]],
      viewer_scope: user && Dawarich.Maps.principal(user, conn.assigns[:locale] || "en")
    }

    RailsAuth.live_session(conn)
    |> Map.put("public_map_capability", capability)
    |> Map.put(
      "public_unlock_token",
      DawarichWeb.RailsCsrf.masked_form_token(
        conn.assigns[:rails_session] || %{},
        "/s/#{capability.id}/unlock",
        "post"
      )
    )
  end

  def on_mount(:default, params, session, socket) do
    capability = session["public_map_capability"]
    connection = if connected?(socket), do: get_connect_info(socket, :session) || %{}, else: nil

    capability =
      if connection && capability,
        do: Map.put(capability, :proof, (connection["shared_link_proofs"] || %{})[capability.id]),
        else: capability

    capability =
      if connection && capability && capability.viewer_scope &&
           connection["rails_user_id"] != capability.viewer_scope.user.id,
         do: Map.put(capability, :viewer_scope, nil),
         else: capability

    socket =
      socket
      |> assign(for key <- @layout, do: {key, session[Atom.to_string(key)]})
      |> assign(
        public_capability: capability,
        public_config: nil,
        public_presentation: nil,
        public_error: nil,
        native: true,
        current_user: nil,
        current_scope: nil,
        navbar: nil,
        page_title: nil,
        flash_messages: [],
        now: DateTime.utc_now()
      )

    if capability && params["id"] == capability.id do
      socket
      |> attach_hook(:public_admission_event, :handle_event, fn _, _, s -> authorize(s) end)
      |> attach_hook(:public_admission_params, :handle_params, fn next, _, s ->
        if next["id"] == s.assigns.public_capability.id,
          do: authorize(s),
          else: {:halt, refuse(s, :not_found)}
      end)
      |> attach_hook(:public_admission_info, :handle_info, fn _, s -> authorize(s) end)
      |> attach_hook(:public_admission_async, :handle_async, fn _, _, s -> authorize(s) end)
      |> authorize()
      |> then(fn {_, next} -> {:cont, next} end)
    else
      {:cont, refuse(socket, :not_found)}
    end
  end

  def authorize(socket) do
    with {:ok, config} <- Public.config(socket.assigns.public_capability),
         {:ok, presentation} <- Public.presentation(socket.assigns.public_capability) do
      old = socket.assigns.public_config

      revision =
        if old && Map.drop(old, ["revision"]) == config,
          do: old["revision"],
          else: ((old && old["revision"]) || 0) + 1

      config = Map.put(config, "revision", revision)

      socket =
        assign(socket,
          public_config: config,
          public_presentation: presentation,
          public_error: nil,
          page_title: config["title"]
        )
        |> DawarichWeb.PublicMapDeadline.schedule()

      {:cont,
       if(connected?(socket) && old && old != config,
         do: push_event(socket, "map:config", config),
         else: socket
       )}
    else
      {:error, reason} -> {:halt, refuse(socket, reason)}
    end
  end

  def refuse(socket, reason) do
    socket
    |> DawarichWeb.MapLive.Subscriptions.release()
    |> DawarichWeb.PublicMapDeadline.cancel()
    |> assign(
      public_config: nil,
      public_presentation: nil,
      public_error: reason,
      page_title: nil,
      public_map_ready: false
    )
    |> push_event("map:clear", %{code: Atom.to_string(reason)})
  end
end
