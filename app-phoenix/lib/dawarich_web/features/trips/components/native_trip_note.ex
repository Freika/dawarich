defmodule DawarichWeb.NativeTripNote do
  @moduledoc false
  use DawarichWeb, :html
  attr :day, :map, required: true
  attr :editor, :map, default: nil
  attr :locale, :string, required: true
  attr :trip_id, :integer, required: true

  def note(assigns) do
    assigns = assign(assigns, :date, Date.to_iso8601(assigns.day.date))

    ~H"""
    <%= if @editor && @editor.date == @date do %>
      <form id="native-trip-note-form" phx-submit="trip:note:save" class="space-y-3">
        <p :if={@editor.errors != []} role="alert" class="text-error [overflow-wrap:anywhere]">
          {Enum.join(@editor.errors, ", ")}
        </p>
        <textarea
          name="note[body]"
          class="textarea textarea-bordered w-full min-w-0"
          maxlength="10000"
          aria-label={t(@locale, "trips.notes.form.write_your_notes_for_this_day", %{})}
          placeholder={t(@locale, "trips.notes.form.write_your_notes_for_this_day", %{})}
          phx-no-format
        >{@editor.body}</textarea>
        <div class="flex gap-2">
          <button type="submit" class="btn btn-sm btn-primary h-auto whitespace-normal">{t(
            @locale,
            "trips.notes.form.save_note",
            %{}
          )}</button>
          <button
            type="button"
            phx-click="trip:note:cancel"
            class="btn btn-sm btn-ghost h-auto whitespace-normal"
          >{t(@locale, "trips.notes.form.cancel", %{})}</button>
        </div>
      </form>
    <% else %>
      <div data-note-display={@date}>
        <%= if @day.note do %>
          <div class="whitespace-pre-wrap text-sm text-base-content/80 mb-3" phx-no-format>{@day.note.body}</div>
          <div class="flex gap-2">
            <button
              phx-click="trip:note:edit"
              phx-value-day={@date}
              data-date={@date}
              class="btn btn-xs btn-ghost"
            >{t(@locale, "trips.notes.note.edit", %{})}</button>
            <form
              class="button_to"
              method="post"
              action={"/trips/#{@trip_id}/notes/#{@day.note.id}"}
              phx-submit="trip:note:delete"
            >
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="day" value={@date} />
              <button
                type="submit"
                class="btn btn-xs btn-ghost text-error"
              >{t(@locale, "trips.notes.note.delete", %{})}</button>
              <input type="hidden" name="authenticity_token" value="" />
            </form>
          </div>
        <% else %>
          <button
            phx-click="trip:note:edit"
            phx-value-day={@date}
            data-date={@date}
            class="btn btn-sm btn-ghost"
          >{t(@locale, "trips.notes.empty.add_note", %{})}</button>
        <% end %>
      </div>
    <% end %>
    """
  end
end
