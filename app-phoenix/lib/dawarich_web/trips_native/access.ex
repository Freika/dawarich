defmodule DawarichWeb.TripsNative.Access do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, detach_hook: 3, redirect: 2]

  alias Dawarich.Accounts
  alias Dawarich.Accounts.Scope

  @derive {Inspect, only: [:actor_id, :locale]}
  defstruct [:actor_id, :locale, :identity]

  @timeout 10_000

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
    socket = cancel_all(socket)
    assigns = Map.take(socket.assigns, [:__changed__, :locale, :flash])
    socket = %{socket | assigns: assigns, private: Map.delete(socket.private, :trips_principal)}
    redirect(socket, to: "/users/sign_in")
  end

  def advance(socket) do
    socket = cancel_all(socket)
    put_runs(socket, %{generation: runs(socket).generation + 1, active: %{}})
  end

  def start(socket, kind, fingerprint, reader) do
    if Phoenix.LiveView.connected?(socket) do
      state = runs(socket)
      socket = cancel(socket, state.active[kind])
      state = runs(socket)
      run = {kind, state.generation, make_ref(), fingerprint}
      timer = Process.send_after(self(), {:data_read_timeout, run}, @timeout)
      principal = socket.private[:trips_principal]

      socket
      |> put_runs(%{state | active: Map.put(state.active, kind, {run, timer})})
      |> Phoenix.LiveView.start_async(run, fn ->
        with {:ok, scope} <- admit(principal), do: reader.(scope)
      end)
    else
      socket
    end
  end

  def finish(socket, {kind, _, _, _} = run, result) do
    case runs(socket).active[kind] do
      {^run, timer} ->
        Process.cancel_timer(timer)
        state = runs(socket)
        socket = put_runs(socket, %{state | active: Map.delete(state.active, kind)})

        case {scope(socket), result} do
          {{:error, reason}, _} -> {:error, reason, socket}
          {_, {:ok, {:ok, value}}} -> {:ok, value, socket}
          {_, {:ok, {:error, reason}}} -> {:error, reason, socket}
          {_, {:error, reason}} -> {:error, reason, socket}
          _ -> {:error, :unavailable, socket}
        end

      _ ->
        {:stale, socket}
    end
  end

  def finish(socket, _run, _result), do: {:stale, socket}

  def timeout(socket, {kind, _, _, _} = run) do
    case runs(socket).active[kind] do
      {^run, _timer} ->
        socket = Phoenix.LiveView.cancel_async(socket, run)
        finish(socket, run, {:error, :timeout})

      _ ->
        {:stale, socket}
    end
  end

  def timeout(socket, _run), do: {:stale, socket}

  def cancel_all(socket),
    do: Enum.reduce(Map.values(runs(socket).active), socket, &cancel(&2, &1))

  defp cancel(socket, nil), do: socket

  defp cancel(socket, {{kind, _, _, _} = run, timer}) do
    Process.cancel_timer(timer)
    state = runs(socket)

    socket
    |> Phoenix.LiveView.cancel_async(run)
    |> put_runs(%{state | active: Map.delete(state.active, kind)})
  end

  defp runs(socket), do: socket.private[:trips_runs] || %{generation: 0, active: %{}}

  defp put_runs(socket, runs),
    do: %{socket | private: Map.put(socket.private, :trips_runs, runs)}

  defp identity(%{encrypted_password: hash}) when is_binary(hash) and byte_size(hash) >= 29,
    do: :crypto.hash(:sha256, binary_part(hash, 0, 29))

  defp identity(_user), do: nil

  defp redact(user), do: %{user | encrypted_password: nil, api_key: nil, settings: %{}}
end
