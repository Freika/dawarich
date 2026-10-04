defmodule DawarichWeb.TripItinerary do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  import DawarichWeb.TripPlanItems, only: [it: 2, it: 3, trek_url: 1, reservation: 1, stay: 1]
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  attr :plan, :map, required: true
  attr :notes, :map, required: true
  attr :plan_on_map, :boolean, required: true
  attr :now, :any, required: true
  attr :locale, :string, required: true

  def itinerary(assigns) do
    assigns =
      assign(
        assigns,
        :unscheduled,
        Enum.filter(assigns.plan.reservations, &is_nil(&1.planned_day_id))
      )

    ~H"""
    <section class="mb-6 rounded-lg border border-base-content/10" aria-labelledby="trip-plan-title">
      <header class="border-b border-base-content/10 px-4 py-3">
        <div class="flex flex-wrap items-start justify-between gap-x-3 gap-y-2">
          <div class="min-w-0">
            <h2 id="trip-plan-title" class="text-lg font-semibold">{it(@locale, "title")}</h2>
            <p class="text-sm text-base-content/60">{it(@locale, "subtitle")}</p>
          </div>
          <span :if={@plan.trip.source_status == 1} class="badge badge-warning shrink-0">{it(
            @locale,
            "sync_stopped"
          )}</span>
        </div>
        <p class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-base-content/60">
          <span :if={@plan.trip.source_synced_at}>{it(@locale, "synced_ago", %{
            time: DawarichWeb.TimeAgo.words(@locale, @plan.trip.source_synced_at, @now)
          })}</span>
          <span :if={@plan.days != []} class="tabular-nums">{it(@locale, "days_count", %{
            count: length(@plan.days)
          })} · {it(@locale, "stops_count", %{
            count: Enum.sum(Enum.map(@plan.days, &length(&1.stops)))
          })}</span>
          <span :if={@plan.travellers != []} class="inline-flex min-w-0 items-center gap-1">
            <.icon name="users" class="size-3.5 shrink-0" />
            <span class="sr-only">{it(@locale, "travellers")}:</span>
            <span class="[overflow-wrap:anywhere]">{Enum.map_join(@plan.travellers, ", ", & &1.name)}</span>
          </span>
          <a
            :if={trek_url(@plan)}
            href={trek_url(@plan)}
            target="_blank"
            rel="noopener noreferrer"
            class="link link-hover inline-flex items-center gap-1"
          >{it(@locale, "open_in_trek")}<.icon name="external-link" class="size-3.5" /></a>
        </p>
      </header>
      <ol :if={@plan.days != []} class="divide-y divide-base-content/10">
        <DawarichWeb.TripItineraryDay.day
          :for={{day, index} <- Enum.with_index(@plan.days)}
          day={day}
          number={index + 1}
          note={@notes[day.date]}
          plan_on_map={@plan_on_map}
          locale={@locale}
        />
      </ol>
      <div :if={@unscheduled != []} class="border-t border-base-content/10 px-4 py-3">
        <h3 class="text-sm font-semibold">{it(@locale, "unscheduled_reservations")}</h3>
        <ul class="mt-2 space-y-2">
          <.reservation :for={reservation <- @unscheduled} item={reservation} locale={@locale} />
        </ul>
      </div>
      <div :if={@plan.unplanned_places != []} class="border-t border-base-content/10 px-4 py-3">
        <h3 class="text-sm font-semibold">{it(@locale, "unplanned_places")}</h3>
        <ul class="mt-2 space-y-1 text-sm">
          <li :for={place <- @plan.unplanned_places}>
            <span class="font-medium [overflow-wrap:anywhere]">{place.name}</span><span
              :if={Ruby.present?(place.address)}
              class="text-xs text-base-content/60 [overflow-wrap:anywhere]"
            > · {place.address}</span>
          </li>
        </ul>
      </div>
      <div :if={@plan.accommodations != []} class="border-t border-base-content/10 px-4 py-3">
        <h3 class="text-sm font-semibold">{it(@locale, "accommodations")}</h3>
        <ul class="mt-2 space-y-2 text-sm">
          <.stay :for={stay <- @plan.accommodations} item={stay} locale={@locale} />
        </ul>
      </div>
    </section>
    """
  end
end
