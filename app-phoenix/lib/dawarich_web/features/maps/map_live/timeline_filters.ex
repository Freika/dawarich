defmodule DawarichWeb.MapLive.TimelineFilters do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2]
  alias Dawarich.Maps
  alias DawarichWeb.MapLive.Commands

  @timeout 15_000

  def handle_event("calendar:month", %{"month" => month}, socket) when is_binary(month) do
    scope = socket.assigns.current_scope
    loader = socket.assigns[:calendar_loader] || (&Maps.Timeline.calendar(&1, &2))
    timeout = socket.assigns[:calendar_timeout] || @timeout
    previous = socket.assigns[:calendar] || %{summary: nil, run: nil}

    {run, socket} =
      DawarichWeb.MapLive.Runs.start(
        socket,
        :calendar,
        previous[:run],
        fn ->
          loader.(scope, month)
        end,
        timeout
      )

    {:noreply,
     assign(socket, :calendar, %{
       status: :loading,
       run: run,
       month: month,
       summary: previous.summary
     })}
  end

  def handle_event("calendar:day", %{"date" => date}, socket) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, _} ->
        range = %{"date" => date, "start_at" => date <> "T00:00", "end_at" => date <> "T23:59"}
        {:noreply, push_patch(socket, to: Commands.path(socket.assigns.map_url, range))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def handle_async({:calendar, run}, result, socket) do
    case socket.assigns[:calendar] do
      %{run: ^run} = calendar -> {:noreply, assign(socket, :calendar, settle(calendar, result))}
      _ -> {:noreply, socket}
    end
  end

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp settle(calendar, {:ok, {:ok, summary}}), do: %{calendar | status: :ready, summary: summary}
  defp settle(calendar, {:ok, {:error, reason}}), do: %{calendar | status: {:error, reason}}
  defp settle(calendar, _), do: %{calendar | status: {:error, :unavailable}}
end
