defmodule DawarichWeb.NativeTripNote do
  @moduledoc false
  use DawarichWeb, :html
  attr :day, :map, required: true
  attr :editor, :map, default: nil
  attr :locale, :string, required: true

  def note(assigns) do
    assigns = assign(assigns, :date, Date.to_iso8601(assigns.day.date))

    ~H"""
    <div class="min-w-0">
      <%= if @editor && @editor.date == @date do %>
        <form id="native-trip-note-form" phx-submit="trip:note:save" class="space-y-3">
          <p :if={@editor.errors != []} role="alert" class="text-error [overflow-wrap:anywhere]">
            {Enum.join(@editor.errors, ", ")}
          </p>
          <textarea
            name="note[body]"
            class="textarea textarea-bordered w-full min-w-0"
            maxlength="10000"
            placeholder={t(@locale, "trips.notes.form.write_your_notes_for_this_day", %{})}
            phx-no-format
          >{@editor.body}</textarea>
          <div class="flex flex-wrap gap-2">
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
        <p :if={@day.note} class="whitespace-pre-wrap [overflow-wrap:anywhere]">{@day.note.body}</p>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="trip:note:edit"
            phx-value-day={@date}
            class="btn btn-sm btn-ghost h-auto whitespace-normal"
          >{t(
            @locale,
            if(@day.note, do: "trips.notes.note.edit", else: "trips.notes.empty.add_note"),
            %{}
          )}</button>
          <button
            :if={@day.note}
            type="button"
            phx-click="trip:note:delete"
            phx-value-day={@date}
            data-confirm={t(@locale, "trips.notes.note.delete_this_note", %{})}
            class="btn btn-sm btn-ghost text-error h-auto whitespace-normal"
          >{t(@locale, "trips.notes.note.delete", %{})}</button>
        </div>
      <% end %>
    </div>
    """
  end
end
