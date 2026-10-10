defmodule DawarichWeb.NativeTripsLive.Form do
  @moduledoc false
  use DawarichWeb, :live_view

  alias Dawarich.Trips.{Commands, Pages}
  alias DawarichWeb.TripsNative.{Access, FormParts, RichUpload}

  @fields ~w(name started_at ended_at)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       trip: nil,
       errors: [],
       values: %{},
       status: :ready,
       rich_description_sgid: nil
     ), temporary_assigns: [rich_description_sgid: nil]}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    id = if socket.assigns.live_action == :edit, do: params["id"]

    with {:ok, scope} <- Access.scope(socket),
         {:ok, trip} <- Pages.form(scope, id, DateTime.utc_now()) do
      {:noreply,
       assign(socket,
         trip: Map.take(trip, [:id, :name, :managed, :trek_url]),
         values: trip.values,
         errors: [],
         status: :ready,
         rich_description_sgid: trip.description,
         page_title: title(socket.assigns.locale, trip.id)
       )}
    else
      error -> {:noreply, refuse(socket, error)}
    end
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{trip: nil}} = socket)
      when event in ~w(validate save),
      do: {:noreply, socket}

  def handle_event("validate", %{"trip" => params}, socket) when is_map(params),
    do: {:noreply, assign(socket, values: scalar(params, socket.assigns.values))}

  def handle_event("save", %{"trip" => params}, socket) when is_map(params) do
    values = scalar(params, socket.assigns.values)

    with {:ok, scope} <- Access.scope(socket) do
      socket |> assign(values: values) |> save(scope, attrs(params, values))
    else
      error -> {:noreply, refuse(socket, error)}
    end
  end

  def handle_event(event, params, socket)
      when event in ~w(rich_upload_reserve rich_upload_claim rich_upload_cancel),
      do: RichUpload.handle(event, params, socket)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save(socket, scope, attrs) do
    now = DateTime.utc_now()

    result =
      case socket.assigns.trip.id do
        nil -> Commands.create(scope, attrs, now)
        id -> Commands.update(scope, id, attrs, now)
      end

    case result do
      {:ok, %{id: id, notice: notice}} ->
        {:noreply,
         socket
         |> put_flash(:notice, t(socket.assigns.locale, notice, %{}))
         |> push_navigate(to: "/trips/#{id}")}

      {:invalid, errors, values} ->
        {:noreply, assign(socket, errors: errors, values: values.values)}

      {:error, :attachment_refused} ->
        {:noreply, assign(socket, status: :attachment_refused)}

      error ->
        {:noreply, refuse(socket, error)}
    end
  end

  defp scalar(params, previous) do
    Enum.reduce(@fields, previous, fn field, acc ->
      case params[field] do
        value when is_binary(value) -> Map.put(acc, field, value)
        _ -> acc
      end
    end)
  end

  defp attrs(params, values) do
    attrs = Map.take(values, @fields)

    case params["rich_description_sgid"] do
      body when is_binary(body) -> Map.put(attrs, "description", body)
      _ -> attrs
    end
  end

  defp refuse(socket, {:error, :stale_session}), do: Access.refuse(socket)
  defp refuse(_socket, {:error, :not_found}), do: raise(DawarichWeb.NotFoundError)

  defp refuse(socket, {:error, :inactive}) do
    socket
    |> put_flash(
      :notice,
      t(socket.assigns.locale, "controllers.application.your_account_is_not_active", %{})
    )
    |> redirect(to: "/")
  end

  defp refuse(socket, _error), do: assign(socket, status: :unavailable)

  defp title(locale, id),
    do: t(locale, if(id, do: "trips.edit.editing_trip", else: "trips.new.new_trip"), %{})

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto my-5 w-full md:w-2/3">
      <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between mb-6">
        <h1 class="text-3xl font-bold min-w-0">{title(@locale, @trip && @trip.id)}</h1>
      </div>
      <div :if={@status == :unavailable} role="alert" class="alert alert-error mb-4">
        {t(@locale, "controllers.application.admin_action_failed", %{})}
      </div>
      <FormParts.trip_form
        :if={@trip}
        trip={@trip}
        values={@values}
        errors={@errors}
        status={@status}
        rich_description_sgid={@rich_description_sgid}
        locale={@locale}
      />
    </div>
    """
  end
end
