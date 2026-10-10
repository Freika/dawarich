defmodule DawarichWeb.PlacesLive.Form do
  @moduledoc false
  import Phoenix.Component
  import Phoenix.LiveView
  alias Dawarich.Places
  alias DawarichWeb.{OrdinaryForm, PlacesUI}
  alias DawarichWeb.PlacesLive.{Index, Nearby}

  def open(socket, :create, _) do
    with {:ok, tags} <- Places.tags(socket.assigns.places_origin) do
      build(socket, Map.merge(Places.new(), %{id: nil, tags: tags}))
    else
      {:error, reason} -> PlacesUI.refuse(socket, reason)
    end
  end

  def open(socket, :edit, id) do
    case Places.edit(socket.assigns.places_origin, id) do
      {:ok, data} -> build(socket, data)
      {:error, reason} -> socket |> clear() |> PlacesUI.refuse(reason)
    end
  end

  defp build(socket, data) do
    form = OrdinaryForm.new("place-form", Places.change(socket.assigns.places_origin, data))

    socket
    |> Nearby.cancel()
    |> assign(
      form_state: form,
      place_data: data,
      detail: nil,
      note_state: nil,
      confirmation: nil,
      error: nil
    )
  end

  def clear(socket), do: socket |> Nearby.cancel() |> assign(form_state: nil, place_data: nil)

  def validate(socket, gen, attrs) do
    case socket.assigns.form_state do
      %{generation: ^gen, status: :idle} = form ->
        attrs = permitted(attrs)
        cs = Places.change(socket.assigns.places_origin, socket.assigns.place_data, attrs)

        case cs do
          %Ecto.Changeset{} ->
            coords = [:latitude, :longitude]

            changed =
              Enum.any?(
                coords,
                &(Ecto.Changeset.get_field(form.changeset, &1) != Ecto.Changeset.get_field(cs, &1))
              )

            socket = if changed, do: Nearby.cancel(socket), else: socket
            assign(socket, :form_state, OrdinaryForm.validate(form, %{cs | action: :validate}))

          {:error, reason} ->
            PlacesUI.refuse(socket, reason)
        end

      _ ->
        socket
    end
  end

  def save(socket, gen, attrs) do
    case OrdinaryForm.accept(socket.assigns.form_state, gen) do
      {:ok, form} ->
        data = socket.assigns.place_data
        attrs = permitted(attrs)
        opts = Application.get_env(:dawarich, :native_places_write_opts, [])

        result =
          if data.id,
            do: Places.update(socket.assigns.places_origin, data.id, attrs, opts),
            else: Places.create(socket.assigns.places_origin, attrs, opts)

        socket =
          socket |> Nearby.cancel() |> assign(:form_state, OrdinaryForm.finish(form, result))

        case result do
          {:ok, _} ->
            key = if data.id, do: "updated", else: "created"

            socket
            |> clear()
            |> Index.reload()
            |> put_flash(
              :notice,
              DawarichWeb.Translate.t(socket.assigns.locale, "controllers.places." <> key, %{})
            )

          {:partial, %{id: id}, _} ->
            case Places.edit(socket.assigns.places_origin, id) do
              {:ok, saved} ->
                state =
                  OrdinaryForm.validate(
                    socket.assigns.form_state,
                    Places.change(socket.assigns.places_origin, saved)
                  )

                socket
                |> assign(place_data: saved, form_state: state)
                |> Index.reload()
                |> PlacesUI.refuse(:unavailable)

              {:error, reason} ->
                socket |> clear() |> PlacesUI.refuse(reason)
            end

          {:error, %Ecto.Changeset{}} ->
            socket

          {:error, reason} ->
            PlacesUI.refuse(socket, reason)
        end

      _ ->
        socket
    end
  end

  def recover_draft(socket, %{"id" => id, "place" => attrs}) do
    socket = if id == "", do: open(socket, :create, nil), else: open(socket, :edit, id)

    case socket.assigns.form_state do
      %{generation: gen, status: :idle} -> validate(socket, gen, attrs)
      _ -> socket
    end
  end

  def recover_draft(socket, _), do: socket

  def recover(socket) do
    case {socket.assigns.form_state, socket.assigns.place_data} do
      {%{status: :partial}, %{id: id}} -> open(socket, :edit, id)
      _ -> socket
    end
  end

  defp permitted(attrs) when is_map(attrs) do
    fields = ~w(name latitude longitude note source tag_ids)
    Map.take(attrs, fields ++ Enum.map(fields, &("_unused_" <> &1)))
  end

  defp permitted(_), do: %{}
end
