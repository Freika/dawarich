defmodule DawarichWeb.MapLive.Timeline do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias DawarichWeb.MapLive.Runs

  @params ~w(start_at end_at)
  @timeout 30_000

  def refresh(socket, params) do
    params = Map.take(params, @params)
    scope = socket.assigns.current_scope
    loader = socket.assigns[:timeline_loader] || (&Dawarich.Maps.Timeline.feed/3)
    timeout = socket.assigns[:timeline_timeout] || @timeout
    previous = socket.assigns[:timeline] || %{feed: nil, run: nil}

    {run, socket} =
      Runs.start(socket, :timeline, previous[:run], fn -> loader.(scope, params, []) end, timeout)

    assign(socket, :timeline, %{status: :loading, run: run, params: params, feed: previous.feed})
  end

  def filter(socket, params) do
    query = if is_binary(params["q"]), do: String.trim(params["q"]), else: ""
    current = if params["clear"], do: %{}, else: socket.assigns[:timeline_filter] || %{}

    socket
    |> assign(:timeline_filter, Map.put(current, "q", String.slice(query, 0, 100)))
    |> assign(:timeline_selection, nil)
  end

  def toggle_tag(socket, %{"tag" => tag}) when is_binary(tag) do
    tag = tag |> String.downcase() |> String.slice(0, 100)
    current = socket.assigns[:timeline_filter] || %{"q" => ""}
    tags = current["tags"] || []
    tags = if tag in tags, do: List.delete(tags, tag), else: Enum.take(tags ++ [tag], 20)

    socket
    |> assign(:timeline_filter, Map.put(current, "tags", tags))
    |> assign(:timeline_selection, nil)
  end

  def toggle_tag(socket, _params), do: socket

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
