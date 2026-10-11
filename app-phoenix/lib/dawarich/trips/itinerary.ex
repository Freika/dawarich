defmodule Dawarich.Trips.Itinerary do
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def trek_url(plan) do
    if plan.source && Ruby.present?(plan.trip.source_identifier) do
      String.replace_suffix(plan.source.base_url, "/", "") <>
        "/trips/" <> URI.encode(plan.trip.source_identifier, &URI.char_unreserved?/1)
    end
  end

  def prepare(plan, settings) do
    local = fn reservation ->
      Map.update!(reservation, :starts_at, fn at ->
        if at do
          Dawarich.UserTimeZone.local(settings, at).local
        end
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
end
