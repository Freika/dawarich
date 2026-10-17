defmodule DawarichWeb.PlacesLive.Detail do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView
  alias Dawarich.Places
  alias DawarichWeb.{OrdinaryForm, PlacesUI}
  alias DawarichWeb.PlacesLive.{Form, Index}

  def open(socket, id) do
    socket = socket |> Form.clear() |> clear() |> assign(:confirmation, nil)

    with {:ok, detail} <- Places.detail(socket.assigns.places_origin, id),
         {:ok, data} <- Places.edit(socket.assigns.places_origin, id),
         {:ok, state} <- Form.state(socket, "place-note", data) do
      assign(socket, detail: detail, note_state: state, error: nil)
    else
      {:error, reason} -> PlacesUI.refuse(socket, reason)
    end
  end

  def clear(socket), do: assign(socket, detail: nil, note_state: nil)

  def save(socket, gen, attrs) do
    case OrdinaryForm.accept(socket.assigns.note_state, gen) do
      {:ok, state} ->
        id = socket.assigns.detail.id
        opts = Application.get_env(:dawarich, :native_places_write_opts, [])
        result = Places.update(socket.assigns.places_origin, id, Map.take(attrs, ["note"]), opts)
        socket = assign(socket, :note_state, OrdinaryForm.finish(state, result))

        case result do
          {:ok, _} ->
            socket
            |> open(id)
            |> Index.reload()
            |> put_flash(
              :notice,
              DawarichWeb.Translate.t(socket.assigns.locale, "controllers.places.updated", %{})
            )

          {:partial, _, _} ->
            PlacesUI.refuse(socket, :unavailable)

          {:error, %Ecto.Changeset{}} ->
            socket

          {:error, :not_found} ->
            socket |> clear() |> PlacesUI.refuse(:not_found)

          {:error, reason} ->
            PlacesUI.refuse(socket, reason)
        end

      _ ->
        socket
    end
  end

  def recover(socket) do
    case {socket.assigns.note_state, socket.assigns.detail} do
      {%{status: :partial}, %{id: id}} -> open(socket, id)
      _ -> socket
    end
  end
end
