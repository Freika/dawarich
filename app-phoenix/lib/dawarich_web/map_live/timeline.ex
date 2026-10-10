defmodule DawarichWeb.MapLive.Timeline do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [start_async: 3]

  @params ~w(start_at end_at)

  def refresh(socket, params) do
    params = Map.take(params, @params)
    run = make_ref()
    scope = socket.assigns.current_scope
    loader = socket.assigns[:timeline_loader] || (&Dawarich.Maps.Timeline.feed/3)
    previous = socket.assigns[:timeline] || %{feed: nil}

    socket
    |> assign(:timeline, %{status: :loading, run: run, params: params, feed: previous.feed})
    |> start_async({:timeline, run}, fn -> loader.(scope, params, []) end)
  end

  def reload(socket) do
    case socket.assigns[:timeline] do
      %{params: params} -> refresh(socket, params)
      _ -> socket
    end
  end

  def handle_async({:timeline, run}, result, socket) do
    case socket.assigns[:timeline] do
      %{run: ^run} = timeline -> {:noreply, assign(socket, :timeline, settle(timeline, result))}
      _ -> {:noreply, socket}
    end
  end

  defp settle(timeline, {:ok, {:ok, feed}}), do: %{timeline | status: :ready, feed: feed}
  defp settle(timeline, {:ok, {:error, reason}}), do: %{timeline | status: {:error, reason}}
  defp settle(timeline, {:exit, _}), do: %{timeline | status: {:error, :unavailable}}
end
