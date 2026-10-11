defmodule DawarichWeb.MapLive.VisitPlaceCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]
  alias Dawarich.Maps.VisitPlaces
  alias Dawarich.RubyInteger
  alias DawarichWeb.MapLive.{Runs, VisitCommands}

  def handle_event("visit:place_search", %{"q" => query}, socket) when is_binary(query) do
    case socket.assigns[:visit_dialog] do
      %{id: id} = current when not is_nil(id) ->
        scope = socket.assigns.current_scope
        loader = socket.assigns[:visit_places_loader] || (&VisitPlaces.search/3)
        query = query |> String.trim() |> String.slice(0, 200)
        previous = current.search || %{run: nil, results: nil}

        {run, socket} =
          Runs.start(
            socket,
            :visit_places,
            previous.run,
            fn -> loader.(scope, id, query) end,
            socket.assigns[:visit_places_timeout] || 10_000
          )

        search = %{run: run, query: query, results: previous.results, error: nil}
        {:noreply, assign(socket, :visit_dialog, %{current | search: search})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("visit:place_pick", %{"kind" => kind, "index" => index}, socket)
      when kind in ~w(place area create) do
    with %{id: id, search: %{results: %{} = results, query: query}} = current <-
           socket.assigns[:visit_dialog],
         item when not is_nil(item) <- pick(results, query, kind, RubyInteger.to_i(index)) do
      VisitCommands.settle(
        socket,
        current,
        VisitPlaces.select(socket.assigns.current_scope, id, kind, item)
      )
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def handle_async({:visit_places, run}, result, socket) do
    case socket.assigns[:visit_dialog] do
      %{search: %{run: ^run} = search} = current ->
        search =
          case result do
            {:ok, {:ok, results}} -> %{search | results: results, error: nil}
            {:ok, {:error, reason}} -> %{search | error: reason}
            _ -> %{search | error: :unavailable}
          end

        {:noreply, assign(socket, :visit_dialog, %{current | search: search})}

      _ ->
        {:noreply, socket}
    end
  end

  defp pick(results, _query, "place", index), do: Enum.at(results["places"] || [], index)
  defp pick(results, _query, "area", index), do: Enum.at(results["areas"] || [], index)

  defp pick(results, query, "create", 0) when byte_size(query) >= 2,
    do: %{"name" => query, "origin" => results["origin"]}

  defp pick(_results, _query, _kind, _index), do: nil
end
