defmodule DawarichWeb.NativeTripConfirmation do
  @moduledoc false
  use DawarichWeb, :html
  alias Phoenix.LiveView.JS
  alias DawarichWeb.{NativeTripState, NativeTripEffects, NativeTripNotes}

  def open(event, params, socket) do
    case NativeTripState.refresh(socket) do
      {:ok, socket} ->
        payload = Map.take(params, ["day"])

        day =
          event == "trip:note:delete" && is_binary(payload["day"]) &&
            NativeTripState.day(socket, payload["day"])

        if event != "trip:note:delete" or (day && day.note) do
          {:noreply, assign(socket, :trip_confirmation, %{event: event, payload: payload})}
        else
          {:noreply, assign(socket, :trip_confirmation, nil)}
        end

      {:error, socket} ->
        {:noreply, socket}
    end
  end

  def accept(%{assigns: %{trip_confirmation: %{event: event, payload: payload}}} = socket) do
    socket = assign(socket, :trip_confirmation, nil)

    if event == "trip:note:delete",
      do: NativeTripNotes.handle_event(event, payload, socket),
      else: NativeTripEffects.handle_event(event, payload, socket)
  end

  def accept(socket), do: {:noreply, socket}
  def cancel(socket), do: {:noreply, assign(socket, :trip_confirmation, nil)}

  attr :confirmation, :map, default: nil
  attr :locale, :string, required: true

  def dialog(assigns) do
    ~H"""
    <dialog
      :if={@confirmation}
      open
      id="native-trip-confirmation"
      role="dialog"
      aria-modal="true"
      aria-labelledby="native-trip-confirmation-title"
      class="modal"
      phx-window-keydown="trip:confirmation:cancel"
      phx-key="Escape"
      phx-mounted={JS.push_focus() |> JS.focus_first(to: "#native-trip-confirmation .modal-action")}
      phx-remove={JS.pop_focus() |> JS.focus(to: return_to(@confirmation))}
    >
      <.focus_wrap id="native-trip-confirmation-focus" class="modal-box min-w-0">
        <h2 id="native-trip-confirmation-title" class="font-bold [overflow-wrap:anywhere]">
          {t(@locale, message(@confirmation.event), %{})}
        </h2>
        <div class="modal-action flex-wrap">
          <button type="button" class="btn" phx-click="trip:confirmation:cancel">{t(
            @locale,
            "javascript.common.cancel",
            %{}
          )}</button>
          <button type="button" class="btn btn-primary" phx-click="trip:confirmation:accept">{t(
            @locale,
            "javascript.common.confirm",
            %{}
          )}</button>
        </div>
      </.focus_wrap>
    </dialog>
    """
  end

  defp return_to(%{event: "trip:note:delete", payload: %{"day" => day}}),
    do:
      "#trip-shell [data-note-display='#{day}'] form[phx-submit='trip:note:delete'] button[type=submit]"

  defp return_to(%{event: event}),
    do: "#trip-shell form[phx-submit='#{event}'] button[type=submit]"

  defp message("trip:delete"), do: "trips.show.delete_this_trip_this_cannot_be_undone"

  defp message("trip:recalculate"),
    do: "trips.recalculate_button.recalculate_this_trip_s_path_distance_and_countries_from_your"

  defp message("trip:note:delete"), do: "trips.notes.note.delete_this_note"
end
