defmodule DawarichWeb.PlacesLive.Index do
  @moduledoc false
  use DawarichWeb, :live_view
  on_mount {DawarichWeb.PlacesLiveAuth, :default}
  import DawarichWeb.HumanDatetime, only: [human_datetime: 1]
  import DawarichWeb.Paginator, only: [paginator: 1]
  alias Dawarich.{Places, RubyInteger}
  alias DawarichWeb.PlacesLive.{Detail, Form, Nearby}
  alias DawarichWeb.{PlaceDetail, PlaceForm}
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
       detail: nil,
       note_state: nil,
       place_data: nil,
       nearby_state: nil
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    query = URI.parse(uri).query || ""

    socket =
      socket
      |> Form.clear()
      |> Detail.clear()
      |> assign(
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
  def handle_event("open_detail", %{"id" => id}, socket), do: {:noreply, Detail.open(socket, id)}

  def handle_event("save_place_note", %{"generation" => gen, "place" => attrs}, socket)
      when is_map(attrs), do: {:noreply, Detail.save(socket, gen, attrs)}

  def handle_event("recover_place_note", _, socket), do: {:noreply, Detail.recover(socket)}
  def handle_event("open_create", _, socket), do: {:noreply, Form.open(socket, :create, nil)}

  def handle_event("open_edit", %{"id" => id}, socket),
    do: {:noreply, Form.open(socket, :edit, id)}

  def handle_event("validate_place", %{"generation" => gen, "place" => attrs}, socket),
    do: {:noreply, Form.validate(socket, gen, attrs)}

  def handle_event("save_place", %{"generation" => gen, "place" => attrs}, socket),
    do: {:noreply, Form.save(socket, gen, attrs)}

  def handle_event("recover_place_draft", params, socket),
    do: {:noreply, Form.recover_draft(socket, params)}

  def handle_event("recover_place", _, socket), do: {:noreply, Form.recover(socket)}
  def handle_event("nearby", params, socket), do: {:noreply, Nearby.request(socket, params)}
  def handle_event("select_nearby", params, socket), do: {:noreply, Nearby.select(socket, params)}

  def handle_event("request_delete", %{"id" => id}, socket) do
    with {:ok, place} <- Places.detail(socket.assigns.places_origin, id),
         {:ok, state} <- Form.state(socket, "place-delete", Places.new()) do
      state =
        OrdinaryForm.confirm(state, place.id)

      {:noreply,
       socket
       |> Form.clear()
       |> Detail.clear()
       |> assign(confirmation: state, detail: nil, error: nil)}
    else
      {:error, reason} -> {:noreply, socket |> Form.clear() |> PlacesUI.refuse(reason)}
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
             |> put_flash(
               :notice,
               t(
                 socket.assigns.locale,
                 "controllers.places.place_was_successfully_destroyed",
                 %{}
               )
             )}

          {:error, reason} ->
            {:noreply, PlacesUI.refuse(socket, reason)}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("check_places", _, socket),
    do:
      {:noreply,
       socket |> Form.clear() |> Detail.clear() |> assign(:confirmation, nil) |> reload()}

  def handle_event("cancel_form", _, socket),
    do:
      {:noreply,
       socket |> Form.clear() |> Detail.clear() |> assign(confirmation: nil, detail: nil)}

  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:nearby_timeout, gen, token}, socket),
    do: {:noreply, Nearby.timeout(socket, gen, token)}

  def handle_info(_, socket), do: {:noreply, socket}
  @impl true
  def handle_async({:nearby, _, _} = name, result, socket),
    do: {:noreply, Nearby.finish(socket, name, result)}

  def handle_async(_, _, socket), do: {:noreply, socket}

  defp coordinates(place), do: RubyFloat.to_s(place.lat) <> ", " <> RubyFloat.to_s(place.lon)
end
