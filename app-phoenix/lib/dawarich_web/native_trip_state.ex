defmodule DawarichWeb.NativeTripState do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3, connected?: 1, put_flash: 3]

  def load(socket, id) do
    with {:ok, socket} <- refresh(socket, id) do
      if connected?(socket) do
        {:ok, socket}
      else
        result = Dawarich.Maps.Dependencies.Trip.prepare(socket.assigns.current_scope, id)

        with {:ok, socket} <- refresh(socket, id) do
          {:ok,
           if(result == :ok,
             do: socket,
             else:
               put_flash(
                 socket,
                 :error,
                 DawarichWeb.Translate.t(
                   socket.assigns.locale,
                   "trips.recalculate_button.recalculation_failed_try_again",
                   %{}
                 )
               )
           )}
        end
      end
    end
  end

  def identity(value) when is_binary(value) and byte_size(value) <= 19 do
    case Integer.parse(value) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 -> id
      _ -> 0
    end
  end

  def identity(_), do: 0

  def refresh(socket, id \\ nil) do
    id = id || socket.assigns.page.presentation.id

    case Dawarich.Maps.Dependencies.Trip.view(socket.assigns.current_scope, id) do
      {:ok, page} ->
        choices =
          Map.filter(socket.assigns[:trip_layers] || %{}, fn {key, value} ->
            is_boolean(value) and
              Enum.any?(~w(photos flights plan), &(layer_key(page.presentation, &1) == key))
          end)

        config = Map.merge(page.config, choices)
        page = %{page | config: config}

        label =
          Enum.map_join(
            [page.presentation.started_at, page.presentation.ended_at],
            " – ",
            fn at ->
              DawarichWeb.MapParts.human_date(
                socket.assigns.locale,
                NaiveDateTime.to_date(at.local)
              )
            end
          )

        previous = socket.assigns.page

        socket =
          assign(socket,
            page: Map.put(page, :range_label, label),
            page_title:
              config["title"] |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string(),
            trip_layers: choices
          )

        socket =
          if previous && previous.config != config,
            do: push_event(socket, "map:config", config),
            else: socket

        {:ok, socket}

      {:error, reason} ->
        {:error, DawarichWeb.NativeTripResource.refuse(socket, reason)}
    end
  end

  def layer_key(page, layer) do
    case layer do
      "photos" -> if page.settings.photos, do: "photosEnabled"
      "flights" -> if page.settings.airtrail, do: "flightsEnabled"
      "plan" -> if page.plan_toggle, do: "planEnabled"
      _ -> nil
    end
  end

  def day(socket, date),
    do: Enum.find(socket.assigns.page.presentation.days, &(Date.to_iso8601(&1.date) == date))
end
