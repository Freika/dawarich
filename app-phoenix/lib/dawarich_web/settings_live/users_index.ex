defmodule DawarichWeb.SettingsLive.UsersIndex do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.CoreComponents, only: [input: 1]
  alias Dawarich.Admin.Users
  alias DawarichWeb.{AdminUI, AdminUsersTable, Paginator, SettingsParts}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       create_open: false,
       create_email: "",
       form_version: 0,
       data: %{rows: [], registration: false, search: nil, page: 1, pages: 0},
       query: %{},
       two_factor: SettingsParts.two_factor_available?(),
       page_title: t(socket.assigns[:locale] || "en", "settings.users.index.users", %{})
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case page(params, socket.assigns) do
      {:ok, page} -> {:noreply, assign(socket, page)}
      {:error, reason} -> {:noreply, AdminUI.refuse(socket, reason)}
    end
  end

  def page(params, context) do
    with {:ok, data} <- Users.list(context.current_scope, params) do
      {:ok,
       %{
         data: data,
         query: Map.take(params, ~w(search page)),
         registration_form: to_form(%{"registration_enabled" => data.registration}, as: nil),
         page_title: t(context.locale, "settings.users.index.users", %{}),
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) when is_binary(search) do
    path =
      if search == "",
        do: "/settings/users",
        else: "/settings/users?" <> URI.encode_query(%{"search" => search})

    {:noreply, push_patch(socket, to: path)}
  end

  def handle_event("open_create", _, socket), do: {:noreply, assign(socket, :create_open, true)}

  def handle_event("update_registration", params, socket) do
    case Users.update_registration(socket.assigns.current_scope, params) do
      {:ok, value} ->
        {:noreply,
         socket
         |> assign(:data, %{socket.assigns.data | registration: value})
         |> assign(:registration_form, to_form(%{"registration_enabled" => value}, as: nil))
         |> AdminUI.notice("controllers.settings.users.user_registration_has_been_status", %{
           status: if(value == true, do: "enabled", else: "disabled")
         })}

      {:error, reason} ->
        {:noreply, AdminUI.refuse(socket, reason)}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, AdminUI.refuse(socket, :invalid_input)}
end
