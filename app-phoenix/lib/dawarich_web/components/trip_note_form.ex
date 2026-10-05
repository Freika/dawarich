defmodule DawarichWeb.TripNoteForm do
  @moduledoc false
  use DawarichWeb, :html

  attr :note, :map, required: true
  attr :trip_id, :integer, required: true
  attr :date, :string, required: true
  attr :locale, :string, required: true
  attr :csrf, :string, required: true
  attr :errors, :list, default: []
  attr :mode, :atom, default: :note

  def editor(assigns) do
    key =
      case assigns.mode do
        :empty -> "empty"
        :note -> "note"
        :error -> "form"
      end

    assigns = assign(assigns, :key, "trips.notes.#{key}.")

    ~H"""
    <form
      class="space-y-3"
      action={"/trips/#{@trip_id}/notes" <> if(@note.id, do: "/#{@note.id}", else: "")}
      accept-charset="UTF-8"
      method="post"
    >
      <input :if={@note.id} type="hidden" name="_method" value="patch" />
      <input type="hidden" name="authenticity_token" value={@csrf} />
      <input value={@date} type="hidden" name="note[date]" id={if @mode != :empty, do: "note_date"} />
      <div :if={@errors != []} class="alert alert-error text-sm">{Enum.join(@errors, ", ")}</div>
      <div>
        <textarea
          name="note[body]"
          class="textarea textarea-bordered w-full min-h-[100px]"
          maxlength="10000"
          placeholder={t(@locale, @key <> "write_your_notes_for_this_day", %{})}
          phx-no-format
        >{@note.body}</textarea>
      </div>
      <div class="flex gap-2">
        <%= if @mode == :empty do %>
          <button type="submit" class="btn btn-primary btn-sm">{t(@locale, @key <> "save_note", %{})}</button>
        <% else %>
          <input
            type="submit"
            name="commit"
            value={t(@locale, @key <> if(@note.id, do: "update_note", else: "save_note"), %{})}
            class="btn btn-primary btn-sm"
            data-disable-with={
              t(@locale, @key <> if(@note.id, do: "update_note", else: "save_note"), %{})
            }
          />
        <% end %>
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          data-action="click->trip-maplibre#hideNoteForm"
          data-date={@date}
        >{t(@locale, @key <> "cancel", %{})}</button>
      </div>
    </form>
    """
  end
end
