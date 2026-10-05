defmodule DawarichWeb.TripPlanItems do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.LocalizedDate

  def it(locale, key, bindings \\ %{}), do: t(locale, "trips.source_itinerary." <> key, bindings)

  def visible?(plan),
    do:
      Enum.any?(
        [
          plan.days,
          plan.reservations,
          plan.accommodations,
          plan.travellers,
          plan.unplanned_places
        ],
        &(&1 != [])
      )

  def synced?(nil), do: false

  def synced?(note),
    do:
      Ruby.present?(note.source_digest) and
        note.source_digest == Base.encode16(:crypto.hash(:sha256, note.body || ""), case: :lower)

  def trek_url(plan) do
    if plan.source && Ruby.present?(plan.trip.source_identifier),
      do:
        String.replace_suffix(plan.source.base_url, "/", "") <>
          "/trips/" <> URI.encode(plan.trip.source_identifier, &URI.char_unreserved?/1)
  end

  def prepare(plan, settings) do
    local = fn reservation ->
      Map.update!(reservation, :starts_at, fn at ->
        if at, do: Dawarich.UserTimeZone.local(settings, at).local
      end)
    end

    %{
      plan
      | reservations: Enum.map(plan.reservations, local),
        days:
          Enum.map(plan.days, fn day ->
            %{day | reservations: Enum.map(day.reservations, local)}
          end)
    }
  end

  def details(locale, stop) do
    time = [stop.starts_at, stop.ends_at] |> Enum.filter(&Ruby.present?/1) |> Enum.join("–")

    mode =
      if Ruby.present?(stop.transport_mode),
        do: fallback(locale, "transportation_modes." <> stop.transport_mode, stop.transport_mode)

    duration =
      if stop.duration_minutes != nil,
        do: it(locale, "duration_minutes", %{count: stop.duration_minutes})

    [
      if(Ruby.present?(time), do: time),
      mode,
      if(Ruby.present?(stop.category), do: stop.category),
      duration
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp fallback(locale, key, raw) do
    case Dawarich.I18n.t(locale, key) do
      {:ok, text} ->
        text

      _ ->
        raw
        |> String.replace("_", " ")
        |> String.trim_leading()
        |> String.replace_suffix(" id", "")
        |> String.downcase()
        |> String.capitalize()
    end
  end

  def coordinate(%Decimal{} = value), do: Decimal.to_float(value)

  attr :item, :map, required: true
  attr :locale, :string, required: true

  def reservation(assigns) do
    assigns =
      assign(
        assigns,
        :details,
        [
          if(assigns.item.starts_at,
            do: LocalizedDate.time(assigns.locale, assigns.item.starts_at, "short")
          ),
          if(Ruby.present?(assigns.item.location), do: assigns.item.location)
        ]
        |> Enum.reject(&is_nil/1)
      )

    ~H"""
    <li class="flex items-start gap-2 text-sm">
      <.icon name="calendar-check-2" class="mt-0.5 size-4 shrink-0 text-base-content/50" />
      <div class="min-w-0">
        <p class="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span class="font-medium [overflow-wrap:anywhere]">{@item.title}</span>
          <span :if={Ruby.present?(@item.status)} class="badge badge-ghost badge-sm">{fallback(
            @locale,
            "trips.source_itinerary.reservation_statuses." <> @item.status,
            @item.status
          )}</span>
        </p>
        <p :if={@details != []} class="text-xs tabular-nums text-base-content/60">
          {Enum.join(@details, " · ")}
        </p>
        <p
          :if={Ruby.present?(@item.notes)}
          class="mt-0.5 whitespace-pre-line text-xs text-base-content/70"
        >
          {@item.notes}
        </p>
      </div>
    </li>
    """
  end

  attr :item, :map, required: true
  attr :locale, :string, required: true

  def stay(assigns) do
    dates =
      [assigns.item.starts_on, assigns.item.ends_on]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&LocalizedDate.l(assigns.locale, &1, "short"))
      |> Enum.join(" – ")

    assigns =
      assign(
        assigns,
        :details,
        [
          if(Ruby.present?(assigns.item.address), do: assigns.item.address),
          if(Ruby.present?(dates), do: dates)
        ]
        |> Enum.reject(&is_nil/1)
      )

    ~H"""
    <li class="min-w-0">
      <p class="font-medium [overflow-wrap:anywhere]">{@item.name}</p>
      <p
        :if={@details != []}
        class="text-xs tabular-nums text-base-content/60 [overflow-wrap:anywhere]"
      >
        {Enum.join(@details, " · ")}
      </p>
      <p
        :if={Ruby.present?(@item.notes)}
        class="mt-0.5 whitespace-pre-line text-xs text-base-content/70"
      >
        {@item.notes}
      </p>
    </li>
    """
  end
end
