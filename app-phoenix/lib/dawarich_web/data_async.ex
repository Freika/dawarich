defmodule DawarichWeb.DataAsync do
  @moduledoc false
  require Phoenix.LiveView
  alias Dawarich.Accounts.DataAccess

  def advance(socket) do
    socket = cancel_all(socket)
    put_state(socket, %{generation: state(socket).generation + 1, runs: %{}})
  end

  def register(socket, kind, fingerprint) do
    socket = cancel_kind(socket, kind)
    run = {kind, state(socket).generation, make_ref(), fingerprint}
    timer = Process.send_after(self(), {:data_read_timeout, run}, 10_000)
    state = state(socket)

    {run,
     put_state(socket, %{state | runs: Map.put(state.runs, kind, %{run: run, timer: timer})})}
  end

  def start(socket, kind, fingerprint, inputs, reader) do
    if Phoenix.LiveView.connected?(socket) do
      {run, socket} = register(socket, kind, fingerprint)
      principal = socket.private.data_principal

      Phoenix.LiveView.start_async(socket, run, fn ->
        with {:ok, scope} <- DataAccess.admit(principal), do: reader.(scope, inputs)
      end)
    else
      socket
    end
  end

  def active?(socket, {kind, _, _, _} = run),
    do: get_in(state(socket), [:runs, kind, :run]) == run

  def active?(_, _), do: false

  def timer(socket, {kind, _, _, _}), do: get_in(state(socket), [:runs, kind, :timer])

  def finish(socket, run, result) do
    if active?(socket, run) do
      socket = remove(socket, run)

      case DataAccess.admit(socket.private[:data_principal]) do
        {:ok, _} -> result(socket, result)
        {:error, reason} -> {:error, reason, socket}
      end
    else
      {:stale, socket}
    end
  end

  def timeout(socket, run) do
    case finish(socket, run, {:error, :timeout}) do
      {:error, reason, socket} -> {:error, reason, socket}
      other -> other
    end
  end

  def cancel_all(socket) do
    Enum.reduce(state(socket).runs, socket, fn {_kind, %{run: run}}, acc -> cancel(acc, run) end)
  end

  defp cancel_kind(socket, kind) do
    case state(socket).runs[kind] do
      nil -> socket
      %{run: run} -> cancel(socket, run)
    end
  end

  defp cancel(socket, run) do
    socket
    |> Phoenix.LiveView.cancel_async(run)
    |> remove(run)
  end

  defp remove(socket, {kind, _, _, _}) do
    current = state(socket)
    if timer = current.runs[kind][:timer], do: Process.cancel_timer(timer)
    put_state(socket, %{current | runs: Map.delete(current.runs, kind)})
  end

  defp result(socket, {:ok, {:ok, value}}), do: {:ok, value, socket}
  defp result(socket, {:ok, {:error, reason}}), do: {:error, reason, socket}
  defp result(socket, {:ok, value}), do: {:ok, value, socket}
  defp result(socket, {:error, reason}), do: {:error, reason, socket}
  defp result(socket, {:exit, _}), do: {:error, :unavailable, socket}
  defp result(socket, _), do: {:error, :unavailable, socket}
  defp state(socket), do: socket.private[:data_async] || %{generation: 0, runs: %{}}

  defp put_state(socket, state),
    do: %{socket | private: Map.put(socket.private, :data_async, state)}
end
