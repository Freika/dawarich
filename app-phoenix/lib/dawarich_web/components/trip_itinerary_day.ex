defmodule DawarichWeb.TripItineraryDay do
  @moduledoc false
  use DawarichWeb, :html

  import DawarichWeb.TripPlanItems,
    only: [it: 2, it: 3, synced?: 1, details: 2, coordinate: 1, reservation: 1]

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  attr :day, :map, required: true
  attr :number, :integer, required: true
  attr :note, :any, default: nil
  attr :plan_on_map, :boolean, required: true
  attr :locale, :string, required: true

  def day(assigns) do
    ~H"""
    <li class="px-4 py-3">
      <h3 class="flex flex-wrap items-baseline gap-x-2 text-sm">
        <span class="font-semibold">{it(@locale, "day_number", %{number: @number})}</span>
        <span class="text-base-content/60">{DawarichWeb.LocalizedDate.l(
          @locale,
          @day.date,
          "short_month_day_weekday"
        )}</span>
        <span :if={Ruby.present?(@day.title)} class="min-w-0 font-medium [overflow-wrap:anywhere]">{@day.title}</span>
      </h3>
      <p
        :if={Ruby.present?(@day.notes) and not synced?(@note)}
        class="mt-1 whitespace-pre-line text-sm text-base-content/70"
      >
        {@day.notes}
      </p>
      <ul
        :if={@day.day_notes != [] and not synced?(@note)}
        class="mt-2 space-y-1 text-sm text-base-content/70"
      >
        <li :for={note <- @day.day_notes}>
          <span :if={note.noted_at != nil} class="tabular-nums text-base-content/50">{note.noted_at}</span> {note.body}
        </li>
      </ul>
      <ol :if={@day.stops != []} class="mt-2 space-y-2">
        <li
          :for={{stop, index} <- Enum.with_index(@day.stops)}
          class="grid grid-cols-[1.25rem_minmax(0,1fr)] gap-x-2"
        >
          <span class="text-right text-sm tabular-nums text-base-content/40">{index + 1}</span>
          <div class="min-w-0">
            <%= if @plan_on_map and stop.latitude != nil and stop.longitude != nil do %>
              <button
                type="button"
                class="text-left text-sm font-medium [overflow-wrap:anywhere] hover:underline"
                title={it(@locale, "show_on_map")}
                data-controller="trip-plan-focus"
                data-action="trip-plan-focus#focus"
                data-trip-plan-focus-longitude-param={coordinate(stop.longitude)}
                data-trip-plan-focus-latitude-param={coordinate(stop.latitude)}
              >{stop.name}</button>
            <% else %>
              <p class="text-sm font-medium [overflow-wrap:anywhere]">{stop.name}</p>
            <% end %>
            <p
              :if={Ruby.present?(stop.address)}
              class="text-xs text-base-content/60 [overflow-wrap:anywhere]"
            >
              {stop.address}
            </p>
            <p :if={details(@locale, stop) != []} class="text-xs tabular-nums text-base-content/60">
              {Enum.join(details(@locale, stop), " · ")}
            </p>
            <p
              :if={Ruby.present?(stop.notes)}
              class="mt-0.5 whitespace-pre-line text-xs text-base-content/70"
            >
              {stop.notes}
            </p>
          </div>
        </li>
      </ol>
      <ul :if={@day.reservations != []} class="mt-3 space-y-2">
        <.reservation :for={reservation <- @day.reservations} item={reservation} locale={@locale} />
      </ul>
    </li>
    """
  end
end
