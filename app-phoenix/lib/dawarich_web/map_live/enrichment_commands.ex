defmodule DawarichWeb.MapLive.EnrichmentCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]
  alias Dawarich.Photos.ScopedEnrichment

  def handle_event("enrichment:scan", params, socket) do
    scope = socket.assigns.current_scope
    scanner = socket.assigns[:enrichment_scanner] || (&ScopedEnrichment.scan(&1, &2))
    previous = get_in(socket.assigns, [:enrichment, :run])

    {run, socket} =
      DawarichWeb.MapLive.Runs.start(
        socket,
        :enrichment_scan,
        previous,
        fn -> scanner.(scope, params) end,
        socket.assigns[:enrichment_timeout] || 60_000
      )

    {:noreply, assign(socket, :enrichment, %{status: :scanning, run: run, matched: nil})}
  end

  def handle_event("enrichment:enrich", %{"assets" => assets}, socket) when is_list(assets) do
    case ScopedEnrichment.enrich(socket.assigns.current_scope, assets) do
      {:ok, result} -> {:reply, %{ok: true, result: result}, socket}
      {:error, reason} -> {:reply, %{error: to_string(reason)}, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def cancel(socket) do
    socket =
      case socket.assigns[:enrichment] do
        %{run: run} -> Phoenix.LiveView.cancel_async(socket, {:enrichment_scan, run})
        _ -> socket
      end

    assign(socket, :enrichment, nil)
  end

  def handle_async({:enrichment_scan, run}, result, socket) do
    case socket.assigns[:enrichment] do
      %{run: ^run} = scan -> {:noreply, settle(socket, scan, result)}
      _ -> {:noreply, socket}
    end
  end

  def handle_async(_name, _result, socket), do: {:noreply, socket}

  defp settle(socket, scan, {:ok, {:ok, result}}) do
    socket
    |> assign(:enrichment, %{scan | status: :ready, matched: result["total_matched"]})
    |> push_event("enrichment:matches", %{
      run: inspect(scan.run),
      matches: result["matches"] || []
    })
  end

  defp settle(socket, scan, {:ok, {:error, reason}}),
    do: assign(socket, :enrichment, %{scan | status: {:error, reason}})

  defp settle(socket, scan, _),
    do: assign(socket, :enrichment, %{scan | status: {:error, :unavailable}})
end
