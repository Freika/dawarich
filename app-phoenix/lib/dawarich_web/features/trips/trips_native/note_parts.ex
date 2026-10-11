defmodule DawarichWeb.TripsNative.NoteParts do
  @moduledoc false
  use DawarichWeb, :html

  attr :day, :map, required: true
  attr :draft, :any, default: nil
  attr :errors, :list, default: []
  attr :locale, :string, required: true

  def note(assigns) do
    assigns =
      assigns
      |> assign(:date, Date.to_iso8601(assigns.day.date))
      |> assign(:key, if(assigns.day.note, do: "trips.notes.note.", else: "trips.notes.empty."))

    ~H"""
    <%= if @draft do %>
      <.form
        for={%{}}
        as={:note}
        id={"note-form-#{@date}"}
        phx-change="note_draft"
        phx-submit="note_save"
        class="space-y-3"
      >
        <input type="hidden" name="note[date]" value={@date} />
        <div :if={@errors != []} class="alert alert-error text-sm" role="alert">
          {Enum.join(@errors, ", ")}
        </div>
        <textarea
          name="note[body]"
          class="textarea textarea-bordered w-full min-h-[100px]"
          maxlength="10000"
          aria-label={t(@locale, @key <> "write_your_notes_for_this_day", %{})}
          placeholder={t(@locale, @key <> "write_your_notes_for_this_day", %{})}
          phx-no-format
        >{@draft}</textarea>
        <div class="flex flex-wrap gap-2">
          <button type="submit" class="btn btn-primary btn-sm">
            {t(
              @locale,
              if(@day.note, do: "trips.notes.note.update_note", else: "trips.notes.empty.save_note"),
              %{}
            )}
          </button>
          <button
            type="button"
            class="btn btn-ghost btn-sm"
            phx-click="note_cancel"
            phx-value-date={@date}
          >
            {t(@locale, @key <> "cancel", %{})}
          </button>
        </div>
      </.form>
    <% else %>
      <div :if={@day.note} data-note-display={@date}>
        <div
          class="whitespace-pre-wrap text-sm text-base-content/80 mb-3 [overflow-wrap:anywhere]"
          phx-no-format
        >{@day.note.body}</div>
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            class="btn btn-xs btn-ghost"
            phx-click="note_edit"
            phx-value-date={@date}
          >
            {t(@locale, "trips.notes.note.edit", %{})}
          </button>
          <button
            type="button"
            class="btn btn-xs btn-ghost text-error"
            phx-click="note_delete"
            phx-value-date={@date}
            data-confirm={t(@locale, "trips.notes.note.delete_this_note", %{})}
          >
            {t(@locale, "trips.notes.note.delete", %{})}
          </button>
        </div>
      </div>
      <button
        :if={!@day.note}
        type="button"
        class="btn btn-sm btn-ghost"
        phx-click="note_edit"
        phx-value-date={@date}
      >
        {t(@locale, "trips.notes.empty.add_note", %{})}
      </button>
    <% end %>
    """
  end
end
