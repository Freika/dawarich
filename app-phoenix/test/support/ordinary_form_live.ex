defmodule Dawarich.Test.OrdinaryFormLive do
  use DawarichWeb, :live_view
  import DawarichWeb.CoreComponents

  def mount(_, _, socket) do
    cs =
      Ecto.Changeset.cast({%{name: "Valid", note: ""}, %{name: :string, note: :string}}, %{}, [
        :name,
        :note
      ])

    {:ok,
     assign(socket,
       forms: %{
         "place" => DawarichWeb.OrdinaryForm.new("place", cs),
         "note" => DawarichWeb.OrdinaryForm.new("note", cs)
       },
       saves: 0
     )}
  end

  def handle_event("save", %{"host" => host, "generation" => gen}, socket)
      when host in ["place", "note"] do
    case DawarichWeb.OrdinaryForm.accept(socket.assigns.forms[host], gen) do
      {:ok, form} ->
        form = DawarichWeb.OrdinaryForm.finish(form, {:ok, %{id: 1}})

        {:noreply,
         assign(socket,
           forms: Map.put(socket.assigns.forms, host, form),
           saves: socket.assigns.saves + 1
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <output id="saves">{@saves}</output><.render_form
        :for={{host, state} <- @forms}
        state={state}
        host={host}
      />
    </div>
    """
  end

  attr :state, :any, required: true
  attr :host, :string, default: "place"

  def render_form(assigns) do
    form = Phoenix.Component.to_form(assigns.state.changeset, as: :place, id: assigns.state.id)
    assigns = assign(assigns, :form, form)

    ~H"""
    <form id={@state.id} phx-submit="save">
      <input type="hidden" name="generation" value={@state.generation} />
      <input type="hidden" name="host" value={@host} />
      <DawarichWeb.OrdinaryFormComponents.summary state={@state} />
      <.input field={@form[:name]} label="Name" />
      <.input field={@form[:note]} label="Note" type="textarea" />
      <button type="submit">Save</button>
    </form>
    """
  end
end
