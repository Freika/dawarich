defmodule DawarichWeb.SettingsLive.UserEdit do
  @moduledoc false
  use DawarichWeb, :live_view
  import DawarichWeb.CoreComponents, only: [input: 1]
  alias Dawarich.{Accounts, Admin.Access, Admin.Users}
  alias DawarichWeb.{AdminUI, SettingsParts}
  @statuses ~w(inactive active trial pending_payment)

  @impl true
  def mount(_params, _session, socket),
    do:
      {:ok,
       assign(socket,
         target: nil,
         form: nil,
         form_version: 0,
         two_factor: SettingsParts.two_factor_available?()
       )}

  @impl true
  def handle_params(params, _uri, socket) do
    case page(params, socket.assigns) do
      {:ok, page} ->
        {:noreply, assign(socket, page)}

      {:error, reason} ->
        {:noreply, socket |> assign(target: nil, form: nil) |> AdminUI.refuse(reason)}
    end
  end

  def page(%{"id" => id}, context) do
    with {:ok, target} <- Users.get(context.current_scope, id, :edit) do
      {:ok,
       %{
         page_title: label(context.locale, "editing_user"),
         target: target,
         form: user_form(target),
         two_factor: Map.get_lazy(context, :two_factor, &SettingsParts.two_factor_available?/0)
       }}
    end
  end

  @impl true
  def handle_event("update_user", %{"user" => params}, socket) do
    socket = assign(socket, :form_version, socket.assigns.form_version + 1)

    case Users.update(socket.assigns.current_scope, socket.assigns.target.id, params) do
      {:ok, id} ->
        {:noreply, updated(socket, id)}

      {:error, reason} ->
        email =
          if is_map(params) and is_binary(params["email"]),
            do: params["email"],
            else: socket.assigns.target.email

        {:noreply,
         socket
         |> assign(:form, user_form(%{socket.assigns.target | email: email}))
         |> AdminUI.refuse(reason)}
    end
  rescue
    _ ->
      {:noreply,
       socket
       |> assign(:form_version, Map.get(socket.assigns, :form_version, 0) + 1)
       |> AdminUI.refuse(:unavailable)}
  end

  def handle_event(_, _, socket), do: {:noreply, AdminUI.refuse(socket, :invalid_input)}

  defp updated(socket, id) do
    socket = AdminUI.notice(socket, "controllers.settings.users.user_was_successfully_updated")
    actor = socket.assigns.current_scope.user
    fresh = if id == actor.id, do: Accounts.get(id), else: actor

    cond do
      not Access.same_identity?(actor, fresh) ->
        redirect(socket, to: "/users/sign_in")

      fresh.admin != true ->
        redirect(socket, to: "/")

      true ->
        case page(%{"id" => id}, socket.assigns) do
          {:ok, page} -> assign(socket, page)
          {:error, reason} -> AdminUI.refuse(socket, reason)
        end
    end
  end

  defp user_form(target),
    do:
      to_form(
        %{
          "email" => target.email,
          "admin" => target.admin,
          "status" => Enum.at(@statuses, target.status)
        },
        as: "user"
      )

  defp statuses, do: Enum.map(@statuses, &{&1, &1})
  defp label(locale, key), do: t(locale, "settings.users.edit." <> key, %{})
end
