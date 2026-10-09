defmodule DawarichWeb.SettingsLive.UserShow do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.Admin.Users
  alias DawarichWeb.{AdminUI, NumberFormat, SettingsParts}
  alias Phoenix.LiveView.JS
  embed_templates "user_show/*"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       target: nil,
       target_user: nil,
       counts: %{},
       security_accepted: MapSet.new(),
       rotate_pending: false,
       dialog_open: false,
       two_factor: SettingsParts.two_factor_available?()
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    previous = socket.assigns.target && socket.assigns.target.id

    case page(params, socket.assigns) do
      {:ok, page} ->
        socket = assign(socket, page)

        socket =
          if previous == page.target.id,
            do: socket,
            else: assign(socket, security_accepted: MapSet.new(), rotate_pending: false)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, socket |> assign(target: nil, target_user: nil) |> AdminUI.refuse(reason)}
    end
  end

  def page(%{"id" => id}, context) do
    with {:ok, data} <- Users.get(context.current_scope, id, :show) do
      {:ok,
       %{
         page_title:
           t(context.locale, "settings.users.show.user_email", %{email: data.details.email}),
         target: data.details,
         target_user: data.user,
         counts: data.counts,
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    end
  end

  @impl true
  def handle_event("open_rotate", _, socket),
    do: {:noreply, assign(socket, :rotate_pending, true)}

  def handle_event("cancel_rotate", _, socket),
    do: {:noreply, assign(socket, :rotate_pending, false)}

  def handle_event("rotate_api_key", _, %{assigns: %{rotate_pending: false}} = socket),
    do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  def handle_event(event, _, socket) when event in ~w(rotate_api_key send_password_reset) do
    if MapSet.member?(socket.assigns.security_accepted, event) do
      {:noreply, socket}
    else
      case apply(Users, String.to_existing_atom(event), [
             socket.assigns.current_scope,
             socket.assigns.target.id
           ]) do
        {:ok, _id} ->
          socket =
            socket
            |> assign(:security_accepted, MapSet.put(socket.assigns.security_accepted, event))
            |> assign(:rotate_pending, false)

          socket =
            if event == "rotate_api_key",
              do: reload(socket) |> push_event("close-dialog", %{id: "rotate_api_key"}),
              else: socket

          key =
            if event == "rotate_api_key",
              do: "api_key_has_been_regenerated",
              else: "password_reset_email_has_been_sent"

          {:noreply, AdminUI.notice(socket, "controllers.settings.users." <> key)}

        {:error, :not_found} ->
          {:noreply, socket |> assign(:target_user, nil) |> AdminUI.refuse(:not_found)}

        {:error, reason} ->
          {:noreply, AdminUI.refuse(socket, reason)}
      end
    end
  end

  def handle_event(_, _, socket), do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  defp reload(socket) do
    case page(%{"id" => socket.assigns.target.id}, socket.assigns) do
      {:ok, page} ->
        assign(socket, page)

      {:error, reason} ->
        socket |> assign(target: nil, target_user: nil) |> AdminUI.refuse(reason)
    end
  end

  @impl true
  def render(assigns), do: show(assigns)
  defp label(locale, key), do: t(locale, "settings.users.show." <> key, %{})
  defp status(0), do: {"inactive", "error"}
  defp status(1), do: {"active", "success"}
  defp status(2), do: {"trial", "warning"}
end
