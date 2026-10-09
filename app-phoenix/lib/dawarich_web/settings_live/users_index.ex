defmodule DawarichWeb.SettingsLive.UsersIndex do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.ListParts, only: [page_header: 1]
  import DawarichWeb.CoreComponents, only: [input: 1]
  alias Dawarich.Admin.Users
  alias DawarichWeb.{AdminUI, AdminUserDialogs, AdminUsersTable, Paginator, SettingsParts}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       create_open: false,
       delete_id: nil,
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

  def handle_event("open_create", _, socket),
    do:
      {:noreply,
       assign(socket,
         create_open: true,
         create_email: "",
         form_version: socket.assigns.form_version + 1
       )}

  def handle_event("close_create", _, socket),
    do:
      {:noreply,
       assign(socket,
         create_open: false,
         create_email: "",
         form_version: socket.assigns.form_version + 1
       )}

  def handle_event("create_user", %{"user" => params}, socket) do
    socket = assign(socket, :form_version, socket.assigns.form_version + 1)

    case Users.create(socket.assigns.current_scope, params) do
      {:ok, _id} ->
        {:noreply,
         socket
         |> assign(create_email: "", create_open: false)
         |> reload()
         |> push_event("close-dialog", %{id: "create_user"})
         |> AdminUI.notice("controllers.settings.users.user_was_successfully_created")}

      {:error, reason} ->
        email = if is_map(params) and is_binary(params["email"]), do: params["email"], else: ""
        {:noreply, socket |> assign(:create_email, email) |> AdminUI.refuse(reason)}
    end
  rescue
    _ -> {:noreply, AdminUI.refuse(socket, :unavailable)}
  end

  def handle_event("open_delete", %{"id" => id}, socket) do
    case Users.get(socket.assigns.current_scope, id, :edit) do
      {:ok, target} -> {:noreply, assign(socket, :delete_id, target.id)}
      {:error, reason} -> {:noreply, AdminUI.refuse(socket, reason)}
    end
  end

  def handle_event("cancel_delete", _, socket), do: {:noreply, assign(socket, :delete_id, nil)}

  def handle_event("delete_user", _, %{assigns: %{delete_id: nil}} = socket),
    do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  def handle_event("delete_user", _, socket) do
    case Users.delete(socket.assigns.current_scope, socket.assigns.delete_id) do
      {:ok, :scheduled} ->
        {:noreply,
         socket
         |> assign(:delete_id, nil)
         |> reload()
         |> push_event("close-dialog", %{id: "delete_user"})
         |> AdminUI.notice(
           "controllers.settings.users.user_deletion_has_been_initiated_the_account_will_be_fully"
         )}

      {:error, reason} ->
        {:noreply, AdminUI.refuse(socket, reason)}
    end
  end

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

  defp reload(socket) do
    case page(socket.assigns.query, socket.assigns) do
      {:ok, page} -> assign(socket, page)
      {:error, reason} -> AdminUI.refuse(socket, reason)
    end
  end
end
