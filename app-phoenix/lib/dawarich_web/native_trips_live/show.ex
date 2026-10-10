defmodule DawarichWeb.NativeTripsLive.Show do
  @moduledoc false
  use DawarichWeb, :live_view

  import DawarichWeb.Icon, only: [icon: 1]

  alias Dawarich.Trips.{Commands, Events, Pages}
  alias DawarichWeb.NativeTripsLive.Notes
  alias DawarichWeb.TripsNative.{Access, DetailPresenter, NoteParts, ShowParts}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       trip: nil,
       days: [],
       days_next: nil,
       days_status: :loading,
       from: nil,
       recalculating: false,
       subscribed: nil,
       calculated: nil,
       note_drafts: %{},
       note_errors: %{},
       description_html: nil
     ), temporary_assigns: [description_html: nil]}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    with {:ok, id} <- Pages.id(params["id"]),
         {:ok, scope} <- Access.scope(socket),
         {:ok, detail} <- Pages.get(scope, id, DateTime.utc_now()) do
      {trip, html} = DetailPresenter.present(detail, scope)

      {:noreply,
       socket
       |> Access.advance()
       |> subscribe(id)
       |> reset_notes(id)
       |> assign(
         trip: trip,
         description_html: html,
         from: DetailPresenter.window(detail, params["from"]),
         recalculating: detail.recalculating,
         page_title: title(socket, detail.name)
       )
       |> calculate(scope, id)
       |> load_days()}
    else
      error -> {:noreply, refuse(socket, error)}
    end
  end

  @impl true
  def handle_async(run, result, socket) do
    case Access.finish(socket, run, result) do
      {:ok, %{days: days, next: next}, socket} ->
        {:noreply, assign(socket, days: days, days_next: next, days_status: :ready)}

      {:stale, socket} ->
        {:noreply, socket}

      {:error, reason, socket} when reason in [:stale_session, :not_found] ->
        {:noreply, refuse(socket, {:error, reason})}

      {:error, _reason, socket} ->
        {:noreply, assign(socket, days_status: :failed)}
    end
  end

  @impl true
  def handle_info({:data_read_timeout, run}, socket) do
    case Access.timeout(socket, run) do
      {:stale, socket} -> {:noreply, socket}
      {:error, :stale_session, socket} -> {:noreply, refuse(socket, {:error, :stale_session})}
      {_, _, socket} -> {:noreply, assign(socket, days_status: :failed)}
    end
  end

  def handle_info({:domain_changed, id, :trip}, %{assigns: %{trip: %{id: id}}} = socket) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, detail} <- Pages.get(scope, id, DateTime.utc_now()) do
      {trip, html} = DetailPresenter.present(detail, scope)

      {:noreply,
       socket
       |> assign(trip: trip, description_html: html, recalculating: detail.recalculating)
       |> load_days()}
    else
      error -> {:noreply, refuse(socket, error)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, %{assigns: %{trip: nil}} = socket), do: {:noreply, socket}

  def handle_event("recalculate", _params, socket) do
    command(socket, &Commands.recalculate(&1, socket.assigns.trip.id, DateTime.utc_now()), fn
      socket, %{status: :queued} -> assign(socket, recalculating: true)
      socket, _ -> socket
    end)
  end

  def handle_event("export", %{"format" => format}, socket) when is_binary(format) do
    case Access.scope(socket) do
      {:ok, scope} ->
        case Commands.request_export(scope, socket.assigns.trip.id, format) do
          {:ok, %{notice: notice}} ->
            {:noreply,
             socket
             |> put_flash(:notice, t(socket.assigns.locale, notice, %{}))
             |> redirect(to: "/exports")}

          {:error, :invalid_format} ->
            {:noreply,
             alert(socket, "controllers.trips.unsupported_export_format_choose_gpx_or_geojson")}

          error ->
            {:noreply, refuse(socket, error)}
        end

      error ->
        {:noreply, refuse(socket, error)}
    end
  end

  def handle_event("delete", _params, socket) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, %{notice: notice}} <-
           Commands.delete(scope, socket.assigns.trip.id, DateTime.utc_now()) do
      {:noreply,
       socket
       |> put_flash(:notice, t(socket.assigns.locale, notice, %{}))
       |> push_navigate(to: "/trips")}
    else
      error -> {:noreply, refuse(socket, error)}
    end
  end

  def handle_event("retry_days", _params, socket), do: {:noreply, load_days(socket)}

  def handle_event(event, params, socket)
      when event in ~w(note_edit note_draft note_cancel note_save note_delete) do
    case Notes.handle(event, params, socket) do
      {:refuse, reason} -> {:noreply, refuse(socket, {:error, reason})}
      socket -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp command(socket, fun, after_ok) do
    with {:ok, scope} <- Access.scope(socket),
         {:ok, result} <- fun.(scope) do
      {:noreply,
       socket
       |> put_flash(:notice, t(socket.assigns.locale, result.notice, %{}))
       |> after_ok.(result)}
    else
      {:error, :inactive} ->
        {:noreply, alert(socket, "controllers.application.your_account_is_not_active")}

      error ->
        {:noreply, refuse(socket, error)}
    end
  end

  defp calculate(socket, scope, id) do
    if connected?(socket) and socket.assigns.calculated != id do
      Commands.ensure_calculated(scope, id, DateTime.utc_now())
      assign(socket, calculated: id)
    else
      socket
    end
  end

  defp load_days(%{assigns: %{trip: %{id: id}, from: from}} = socket) do
    socket
    |> assign(days_status: :loading)
    |> Access.start(:days, {id, from}, {id, from}, fn scope, {id, from} ->
      Pages.days(scope, id, from)
    end)
  end

  defp reset_notes(%{assigns: %{trip: %{id: id}}} = socket, id), do: socket
  defp reset_notes(socket, _id), do: assign(socket, note_drafts: %{}, note_errors: %{})

  defp subscribe(%{assigns: %{subscribed: id}} = socket, id), do: socket

  defp subscribe(socket, id) do
    if connected?(socket) do
      if old = socket.assigns.subscribed, do: Events.unsubscribe(old)
      Events.subscribe(id)
      assign(socket, subscribed: id)
    else
      socket
    end
  end

  defp refuse(socket, {:error, :stale_session}), do: Access.refuse(socket)

  defp refuse(%{assigns: %{trip: %{}}} = socket, {:error, :not_found}) do
    socket
    |> Access.cancel_all()
    |> assign(trip: nil, days: [])
    |> put_flash(:alert, t(socket.assigns.locale, "controllers.api.record_not_found", %{}))
    |> push_navigate(to: "/trips")
  end

  defp refuse(_socket, {:error, :not_found}), do: raise(DawarichWeb.NotFoundError)
  defp refuse(socket, _error), do: alert(socket, "controllers.application.admin_action_failed")

  defp alert(socket, key), do: put_flash(socket, :alert, t(socket.assigns.locale, key, %{}))

  defp title(socket, name) do
    escaped = name |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    if connected?(socket),
      do: DawarichWeb.Layouts.page_title(socket.assigns.locale, escaped),
      else: escaped
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={@trip} class="container mx-auto px-4 my-5">
      <div class="flex flex-col lg:flex-row gap-6">
        <div
          class="w-full lg:w-3/5 h-[50vh] lg:h-[calc(100dvh-9.75rem)] shrink-0 rounded-lg bg-base-200"
          data-trip-map-host={@trip.id}
        >
        </div>
        <div class="w-full lg:w-2/5 min-w-0">
          <ShowParts.header trip={@trip} locale={@locale} />
          <ShowParts.recalculate recalculating={@recalculating} locale={@locale} />
          <DawarichWeb.TripItinerary.itinerary
            :if={@trip.plan}
            plan={@trip.plan}
            notes={@trip.notes}
            plan_on_map={false}
            locale={@locale}
            now={DateTime.utc_now()}
          />
          <ShowParts.days
            trip={@trip}
            days={@days}
            status={@days_status}
            previous={DetailPresenter.previous(@trip, @days)}
            next={@days_next}
            locale={@locale}
          >
            <:note :let={day}>
              <NoteParts.note
                day={day}
                draft={@note_drafts[Date.to_iso8601(day.date)]}
                errors={@note_errors[Date.to_iso8601(day.date)] || []}
                locale={@locale}
              />
            </:note>
          </ShowParts.days>
          <ShowParts.description trip={@trip} html={@description_html} locale={@locale} />
          <div class="mb-6">
            <.link navigate="/trips" class="btn btn-sm btn-ghost gap-1">
              <.icon name="arrow-left" class="w-4 h-4" /> {t(@locale, "trips.show.back_to_trips", %{})}
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
