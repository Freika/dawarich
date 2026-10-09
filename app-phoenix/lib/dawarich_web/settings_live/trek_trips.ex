defmodule DawarichWeb.SettingsLive.TrekTrips do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.Integrations.Trek
  @integrations "/settings/integrations?service=trek"

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Trek.list_trips(socket.assigns.current_scope, id, connected?(socket)) do
      {:ok, page} ->
        {:ok,
         socket
         |> assign(page)
         |> assign(:form, to_form(%{}, as: :selection))
         |> assign(:page_title, text(socket, "select_trips.title"))}

      {:error, :not_found} ->
        raise DawarichWeb.NotFoundError

      {:error, reason} ->
        {:ok, failure(socket, reason)}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("import", params, socket) do
    ids = get_in(params, ["selection", "trip_ids"]) || []

    case Trek.import_trips(socket.assigns.current_scope, socket.assigns.source.id, ids) do
      {:ok, result} ->
        key =
          if result == :empty,
            do: "import_trips.no_trips_selected",
            else: "import_trips.trips_are_now_syncing"

        {:noreply,
         socket |> put_flash(:notice, text(socket, key)) |> push_navigate(to: @integrations)}

      {:error, :no_dated_trips} ->
        {:noreply,
         put_flash(socket, :alert, text(socket, "import_trips.select_at_least_one_dated_trip"))}

      {:error, :not_found} ->
        raise DawarichWeb.NotFoundError

      {:error, reason} ->
        {:noreply, failure(socket, reason)}
    end
  end

  defp failure(socket, :inactive),
    do:
      socket
      |> put_flash(
        :notice,
        t(socket.assigns.locale, "controllers.application.your_account_is_not_active", %{})
      )
      |> redirect(to: "/")

  defp failure(socket, :pro_required),
    do:
      socket
      |> put_flash(
        :alert,
        t(socket.assigns.locale, "controllers.application.this_feature_requires_a_pro_plan", %{})
      )
      |> redirect(to: @integrations)

  defp failure(socket, :disabled),
    do:
      socket
      |> put_flash(:alert, text(socket, "sync.source_disabled"))
      |> redirect(to: @integrations)

  defp failure(socket, :importing),
    do:
      socket
      |> put_flash(:alert, text(socket, "sync.source_importing"))
      |> redirect(to: @integrations)

  defp failure(socket, %{message: message}),
    do: socket |> put_flash(:alert, message) |> redirect(to: @integrations)

  defp failure(socket, message) when is_binary(message),
    do: socket |> put_flash(:alert, message) |> redirect(to: @integrations)

  defp text(socket, key), do: t(socket.assigns.locale, "settings.trek_sources." <> key, %{})

  @impl true
  def render(assigns), do: DawarichWeb.TrekSelection.native_form(assigns)
end
