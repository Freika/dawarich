defmodule DawarichWeb.NativeTripState do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  def refresh(socket, id \\ nil) do
    id = id || socket.assigns.page.presentation.id

    case Dawarich.Maps.Dependencies.Trip.view(socket.assigns.current_scope, id) do
      {:ok, page} ->
        config = page.config
        label = config["range"]["startAt"] <> " – " <> config["range"]["endAt"]

        {:ok,
         assign(socket, page: Map.put(page, :range_label, label), page_title: config["title"])}

      {:error, reason} ->
        {:error,
         socket
         |> assign(page_title: nil, selected_day: nil, note_editor: nil)
         |> DawarichWeb.MapLiveAuth.refuse(reason)
         |> push_event("map:clear", %{})}
    end
  end

  def day(socket, date),
    do: Enum.find(socket.assigns.page.presentation.days, &(Date.to_iso8601(&1.date) == date))
end
