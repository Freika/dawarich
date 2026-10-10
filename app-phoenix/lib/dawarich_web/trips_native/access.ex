defmodule DawarichWeb.TripsNative.Access do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, detach_hook: 3, redirect: 2]

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope

  @derive {Inspect, only: [:actor_id, :locale]}
  defstruct [:actor_id, :locale, :identity]

  def on_mount(:require_user, params, session, socket) do
    with {:cont, socket} <-
           DawarichWeb.NativeAuth.on_mount(:require_user, params, session, socket) do
      socket
      |> put_principal(principal(socket.assigns.current_scope))
      |> detach_hook(:rails_user, :handle_event)
      |> detach_hook(:notification_session, :handle_event)
      |> attach_hook(:trips_params, :handle_params, fn _, _, socket -> authorize(socket) end)
      |> attach_hook(:trips_event, :handle_event, fn _, _, socket -> authorize(socket) end)
      |> attach_hook(:trips_info, :handle_info, fn _, socket -> authorize(socket) end)
      |> attach_hook(:trips_async, :handle_async, fn _, _, socket -> authorize(socket) end)
      |> authorize()
    end
  end

  def principal(%Scope{user: %{id: id} = user, locale: locale}),
    do: %__MODULE__{actor_id: id, locale: locale, identity: identity(user)}

  def principal(_scope), do: nil

  def put_principal(socket, principal),
    do: %{socket | private: Map.put(socket.private, :trips_principal, principal)}

  def admit(%__MODULE__{actor_id: id, identity: proof, locale: locale}) do
    with user when not is_nil(user) <- Accounts.get(id),
         current when is_binary(current) <- identity(user),
         true <- is_binary(proof) and Plug.Crypto.secure_compare(proof, current) do
      {:ok, Scope.for_user(user, locale)}
    else
      _ -> {:error, :stale_session}
    end
  end

  def admit(_principal), do: {:error, :stale_session}

  def scope(socket), do: admit(socket.private[:trips_principal])

  def authorize(%{assigns: %{notification_signed_out: true}} = socket),
    do: {:halt, refuse(socket)}

  def authorize(socket) do
    case scope(socket) do
      {:ok, scope} ->
        socket = assign(socket, :current_user, redact(scope.user))
        {:cont, %{socket | assigns: Map.delete(socket.assigns, :current_scope)}}

      {:error, _} ->
        {:halt, refuse(socket)}
    end
  end

  def refuse(socket) do
    assigns = Map.take(socket.assigns, [:__changed__, :locale, :flash])
    socket = %{socket | assigns: assigns, private: Map.delete(socket.private, :trips_principal)}
    redirect(socket, to: "/users/sign_in")
  end

  defp identity(%{encrypted_password: hash}) when is_binary(hash) and byte_size(hash) >= 29,
    do: :crypto.hash(:sha256, binary_part(hash, 0, 29))

  defp identity(_user), do: nil

  defp redact(user), do: %{user | encrypted_password: nil, api_key: nil, settings: %{}}
end
