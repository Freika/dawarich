defmodule DawarichWeb.PlacesLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.PlacesLiveAuth, :default}
  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  alias Dawarich.{Places, RubyInteger}
  alias DawarichWeb.{OrdinaryForm, OrdinaryFormComponents, PlacesUI}
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  @impl true
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       page_title: t(socket.assigns.locale, "places.index.places", %{}),
       entries: [],
       total_pages: 0,
       page: 1,
       query: %{},
       error: nil,
       confirmation: nil,
       form_state: nil,
       detail: nil
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    query = URI.parse(uri).query || ""

    socket =
      assign(socket,
        query: URI.decode_query(query),
        page: max(RubyInteger.to_i(params["page"]), 1),
        confirmation: nil
      )

    {:noreply, reload(socket, params["page"])}
  end

  def reload(socket, page \\ nil) do
    page = page || socket.assigns.query["page"]

    case Places.list(socket.assigns.places_origin, page) do
      {:ok, result} -> socket |> assign(result) |> assign(:error, nil)
      {:error, :stale_session} -> PlacesUI.refuse(socket, :stale_session)
      _ -> socket |> assign(entries: [], total_pages: 0) |> PlacesUI.refuse(:unavailable)
    end
  end

  @impl true
  def handle_event("request_delete", %{"id" => id}, socket) do
    with {:ok, place} <- Places.detail(socket.assigns.places_origin, id) do
      state =
        OrdinaryForm.new(
          "place-delete",
          Places.change(socket.assigns.places_origin, Places.new())
        )
        |> OrdinaryForm.confirm(place.id)

      {:noreply, assign(socket, confirmation: state, form_state: nil, detail: nil, error: nil)}
    else
      {:error, reason} -> {:noreply, PlacesUI.refuse(socket, reason)}
    end
  end

  def handle_event("confirm_delete", %{"generation" => gen}, socket) do
    case OrdinaryForm.accept(socket.assigns.confirmation, gen) do
      {:ok, state} ->
        result = Places.delete(socket.assigns.places_origin, state.confirmation)
        socket = assign(socket, :confirmation, OrdinaryForm.finish(state, result))

        case result do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:confirmation, nil)
             |> reload()
             |> put_flash(:notice, t(socket.assigns.locale, "controllers.places.destroyed", %{}))}

          {:error, reason} ->
            {:noreply, PlacesUI.refuse(socket, reason)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel_form", _, socket),
    do: {:noreply, assign(socket, confirmation: nil, form_state: nil, detail: nil)}

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_async(_, _, socket), do: {:noreply, socket}

  defp coordinates(place), do: RubyFloat.to_s(place.lat) <> ", " <> RubyFloat.to_s(place.lon)
end
