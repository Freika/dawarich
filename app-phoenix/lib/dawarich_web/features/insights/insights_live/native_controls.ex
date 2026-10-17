defmodule DawarichWeb.InsightsLive.NativeControls do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [put_flash: 3, push_patch: 2]
  alias DawarichWeb.NativeDataAuth

  def handle(event, params, socket) do
    with {:ok, scope} <- NativeDataAuth.scope(socket),
         true <- is_map(socket.assigns.data),
         {:ok, _, period} <-
           Dawarich.Analytics.Period.admit(scope, socket.assigns.query, :insights, opts(socket)) do
      if event in ~w(calendar_mode calendar_country) and period.restricted do
        DawarichWeb.InsightsLive.NativePage.handle_params(socket.assigns.query, "", socket)
      else
        apply_event(event, params, scope, socket)
      end
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  defp apply_event("close_dialog", _, _, socket), do: {:noreply, assign(socket, dialog: nil)}

  defp apply_event("open_places", %{"kind" => kind}, scope, socket)
       when kind in ~w(countries cities) do
    with {:ok, data} <-
           Dawarich.Insights.Pages.overview(scope, socket.assigns.query, opts(socket)),
         true <- data.all_time do
      {:noreply,
       assign(socket,
         data: Map.put(data, :more, length(data.available) > data.period.page * 50),
         dialog: kind
       )}
    else
      _ -> {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  defp apply_event("calendar_mode", %{"mode" => mode}, _, socket)
       when mode in ~w(both distance countries) do
    if !socket.assigns.data.restricted,
      do: {:noreply, assign(socket, calendar_mode: mode)},
      else: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
  end

  defp apply_event("calendar_country", %{"country" => name}, _, socket) do
    residency = socket.assigns.residency

    if residency && residency.state == :ready &&
         Enum.any?(residency.value.countries, &(&1.name == name)) do
      country = if socket.assigns.calendar_country == name, do: nil, else: name
      {:noreply, assign(socket, calendar_country: country)}
    else
      {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
    end
  end

  defp apply_event("update", _, scope, socket) do
    data = socket.assigns.data
    params = if data.all_time, do: nil, else: %{"year" => to_string(data.year), "month" => "all"}

    with {:ok, _} <-
           Dawarich.Stats.Commands.update(
             scope,
             params,
             socket.private.insights_receipt,
             opts(socket)
           ) do
      {:noreply,
       socket
       |> put_flash(
         :notice,
         DawarichWeb.Translate.t(
           socket.assigns.locale,
           "controllers.stats.stats_are_being_updated",
           %{}
         )
       )
       |> push_patch(to: "/insights?year=" <> data.selected)}
    else
      {:error, reason} -> {:noreply, NativeDataAuth.refuse(socket, reason)}
    end
  end

  defp apply_event(_, _, _, socket), do: {:noreply, NativeDataAuth.refuse(socket, :invalid_input)}
  defp opts(socket), do: [now: DateTime.utc_now(), self_hosted: socket.assigns.self_hosted]
end
