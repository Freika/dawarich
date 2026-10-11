defmodule DawarichWeb.TripPlanItems do
  @moduledoc false
  use DawarichWeb, :html
  import DawarichWeb.Icon, only: [icon: 1]
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.LocalizedDate

  def it(locale, key, bindings \\ %{}) do
    t(locale, "trips.source_itinerary." <> key, bindings)
  end

  def visible?(plan) do
    Enum.any?(
      [plan.days, plan.reservations, plan.accommodations, plan.travellers, plan.unplanned_places],
      &(&1 != [])
    )
  end

  def synced?(nil) do
    false
  end

  def synced?(note) do
    Ruby.present?(note.source_digest) and
      note.source_digest == Base.encode16(:crypto.hash(:sha256, note.body || ""), case: :lower)
  end

  def details(locale, stop) do
    time = [stop.starts_at, stop.ends_at] |> Enum.filter(&Ruby.present?/1) |> Enum.join("–")

    mode =
      if Ruby.present?(stop.transport_mode) do
        fallback(locale, "transportation_modes." <> stop.transport_mode, stop.transport_mode)
      end

    duration =
      if stop.duration_minutes != nil do
        it(locale, "duration_minutes", %{count: stop.duration_minutes})
      end

    [
      if Ruby.present?(time) do
        time
      end,
      mode,
      if Ruby.present?(stop.category) do
        stop.category
      end,
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

  def coordinate(%Decimal{} = value) do
    Decimal.to_float(value)
  end

  attr(:item, :map, required: true)
  attr(:locale, :string, required: true)

  def reservation(assigns) do
    assigns =
      assign(
        assigns,
        :details,
        [
          if assigns.item.starts_at do
            LocalizedDate.time(assigns.locale, assigns.item.starts_at, "short")
          end,
          if Ruby.present?(assigns.item.location) do
            assigns.item.location
          end
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

  attr(:item, :map, required: true)
  attr(:locale, :string, required: true)

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
          if Ruby.present?(assigns.item.address) do
            assigns.item.address
          end,
          if Ruby.present?(dates) do
            dates
          end
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

  defdelegate trek_url(arg1), to: Dawarich.Trips.Itinerary
  defdelegate prepare(arg1, arg2), to: Dawarich.Trips.Itinerary
end
