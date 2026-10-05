defmodule DawarichWeb.TripDaysList do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.{LocalizedDate, LocalizedTime, TripFormat}

  attr :page, :map, required: true
  attr :locale, :string, required: true
  attr :rails_csrf_token, :string, required: true

  def trip_days(assigns) do
    ~H"""
    <div data-trip-maplibre-target="daysAccordion" class="space-y-1 mb-6">
      <details
        :for={day <- @page.days}
        class="collapse collapse-arrow bg-base-200 rounded-lg"
        data-day-key={Date.to_iso8601(day.date)}
      >
        <summary
          class="collapse-title flex items-center gap-2 text-sm font-medium min-h-0 cursor-pointer"
          data-action="click->trip-maplibre#toggleDay"
          data-trip-maplibre-day-key-param={Date.to_iso8601(day.date)}
        >
          <span
            class="inline-block w-3 h-3 rounded-full flex-shrink-0 bg-base-content/30"
            data-day-dot={Date.to_iso8601(day.date)}
          ></span>
          <span>{LocalizedDate.l(@locale, day.date, "short_month_day_weekday")}</span>
          <%= if day.stats do %>
            <span class="text-base-content/50 text-xs">
              {LocalizedTime.l(@locale, day.stats.first, "hour_minute")} – {LocalizedTime.l(
                @locale,
                day.stats.last,
                "hour_minute"
              )}
            </span>
            <span class="text-base-content/50 ml-auto mr-6 text-xs">
              {t(@locale, "trips.show.middot", %{})}
              {TripFormat.day_distance(@locale, day.stats.distance_m, @page.settings.factor)} {@page.settings.unit}
            </span>
          <% else %>
            <span class="text-base-content/50 ml-auto mr-6 text-xs">{t(
              @locale,
              "trips.show.no_data",
              %{}
            )}</span>
          <% end %>
        </summary>
        <div class="collapse-content">
          <.note
            :if={day.note}
            note={day.note}
            trip_id={@page.id}
            locale={@locale}
            rails_csrf_token={@rails_csrf_token}
          />
          <.empty_note
            :if={!day.note}
            date={Date.to_iso8601(day.date)}
            trip_id={@page.id}
            locale={@locale}
            rails_csrf_token={@rails_csrf_token}
          />
        </div>
      </details>
    </div>
    """
  end

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
