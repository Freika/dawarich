defmodule DawarichWeb.MapLive.TimelineFilters do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_patch: 2, start_async: 3]
  alias Dawarich.{BoundedTask, Entitlements, Maps, RubyInteger}
  alias DawarichWeb.MapLive.Commands

  @timeout 15_000

  def handle_event("calendar:month", %{"month" => month}, socket) when is_binary(month) do
    run = make_ref()
    scope = socket.assigns.current_scope
    loader = socket.assigns[:calendar_loader] || (&Maps.Timeline.calendar(&1, &2))
    timeout = socket.assigns[:calendar_timeout] || @timeout
    previous = socket.assigns[:calendar] || %{summary: nil}

    {:noreply,
     socket
     |> assign(:calendar, %{status: :loading, run: run, summary: previous.summary})
     |> start_async({:calendar, run}, fn ->
       BoundedTask.run(fn -> loader.(scope, month) end, timeout)
     end)}
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

  def handle_event("residency:year", params, socket) do
    year = if is_binary(params["year"]), do: RubyInteger.to_i(params["year"])
    now = DateTime.utc_now()
    hosted = Dawarich.ReleaseMigration.self_hosted?()

    result =
      Maps.with_actor(socket.assigns.current_scope, fn actor ->
        if Entitlements.full_access?(actor, hosted, now),
          do: DawarichWeb.ResidencyFrame.data(actor, year, now),
          else: {:error, :pro_required}
      end)

    case result do
      {:ok, data} -> {:noreply, assign(socket, :residency, data)}
      _ -> {:noreply, assign(socket, :residency, nil)}
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
