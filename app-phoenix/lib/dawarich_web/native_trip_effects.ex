defmodule DawarichWeb.NativeTripEffects do
  @moduledoc false
  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]
  alias DawarichWeb.NativeTripState

  def handle_event(event, payload, socket) do
    case NativeTripState.refresh(socket) do
      {:ok, socket} -> {:noreply, effect(event, payload, socket)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  defp effect("trip:delete", _, socket) do
    case command(socket, :delete) do
      {:ok, :deleted} ->
        socket |> notice("trip_was_successfully_destroyed") |> redirect(to: "/trips")

      _ ->
        error(socket, "export_failed_to_initiate_please_try_again")
    end
  end

  defp effect("trip:recalculate", _, socket) do
    case command(socket, :recalculate) do
      {:ok, result} when result in [:queued, :cooldown] ->
        key =
          if result == :queued,
            do: "recalculating_the_page_will_update_automatically_when_it_s_ready",
            else: "already_recalculating_this_page_will_update_when_it_s_done"

        case NativeTripState.refresh(notice(socket, key)) do
          {:ok, socket} -> socket
          {:error, socket} -> socket
        end

      _ ->
        put_flash(
          socket,
          :error,
          DawarichWeb.Translate.t(
            socket.assigns.locale,
            "trips.recalculate_button.recalculation_failed_try_again",
            %{}
          )
        )
    end
  end

  defp effect("trip:export", %{"format" => format}, socket) do
    case Dawarich.Maps.Dependencies.Trip.export(
           socket.assigns.current_scope,
           socket.assigns.page.presentation.id,
           format
         ) do
      {:ok, _} ->
        socket
        |> notice("trip_export_initiated_check_the_exports_page_when_it_s")
        |> redirect(to: "/exports")

      {:invalid, :format} ->
        error(socket, "unsupported_export_format_choose_gpx_or_geojson")

      _ ->
        error(socket, "export_failed_to_initiate_please_try_again")
    end
  end

  defp effect(_, _, socket), do: socket

  defp command(socket, action),
    do:
      Dawarich.Maps.Dependencies.Trip.command(
        socket.assigns.current_scope,
        socket.assigns.page.presentation.id,
        action
      )

  defp notice(socket, key), do: put_flash(socket, :notice, message(socket, key))
  defp error(socket, key), do: put_flash(socket, :error, message(socket, key))

  defp message(socket, key),
    do: DawarichWeb.Translate.t(socket.assigns.locale, "controllers.trips." <> key, %{})
end
