defmodule DawarichWeb.TripDaysList do
  @moduledoc false
  use DawarichWeb, :html

  attr :note, :map, required: true
  attr :trip_id, :integer, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def note(assigns) do
    assigns = assign(assigns, date: Date.to_iso8601(assigns.note.date))

    ~H"""
    <turbo-frame id={"note-#{@trip_id}-#{@date}"}>
      <div data-note-display={@date}>
        <div class="whitespace-pre-wrap text-sm text-base-content/80 mb-3" phx-no-format>{@note.body}</div>
        <div class="flex gap-2">
          <button
            class="btn btn-xs btn-ghost"
            data-action="click->trip-maplibre#showNoteForm"
            data-date={@date}
          >{n(@locale, "edit")}</button>
          <form class="button_to" method="post" action={"/trips/#{@trip_id}/notes/#{@note.id}"}>
            <input type="hidden" name="_method" value="delete" />
            <button
              class="btn btn-xs btn-ghost text-error"
              data-turbo-confirm={n(@locale, "delete_this_note")}
              type="submit"
            >{n(@locale, "delete")}</button>
            <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
          </form>
        </div>
      </div>
      <div data-note-form={@date} class="hidden">
        <DawarichWeb.TripNoteForm.editor
          note={@note}
          trip_id={@trip_id}
          date={@date}
          locale={@locale}
          csrf={@rails_csrf_token}
        />
      </div>
    </turbo-frame>
    """
  end

  attr :date, :string, required: true
  attr :trip_id, :integer, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def empty_note(assigns) do
    ~H"""
    <turbo-frame id={"note-#{@trip_id}-#{@date}"}>
      <div data-note-display={@date}>
        <button
          class="btn btn-sm btn-ghost"
          data-action="click->trip-maplibre#showNoteForm"
          data-date={@date}
        >{e(@locale, "add_note")}</button>
      </div>
      <div data-note-form={@date} class="hidden">
        <DawarichWeb.TripNoteForm.editor
          note={%{id: nil, body: nil}}
          trip_id={@trip_id}
          date={@date}
          locale={@locale}
          csrf={@rails_csrf_token}
          mode={:empty}
        />
      </div>
    </turbo-frame>
    """
  end

  defp n(locale, key), do: t(locale, "trips.notes.note." <> key, %{})
  defp e(locale, key), do: t(locale, "trips.notes.empty." <> key, %{})
end
