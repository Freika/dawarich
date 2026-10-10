defmodule DawarichWeb.TripsNative.DetailPresenter do
  @moduledoc false

  alias Dawarich.CountryNames
  alias DawarichWeb.TripPlanItems

  def present(detail, scope) do
    plan =
      if detail.plan && TripPlanItems.visible?(detail.plan),
        do: TripPlanItems.prepare(detail.plan, Dawarich.UserSettings.get(scope.user))

    html = if is_binary(detail.description), do: detail.description

    trip =
      detail
      |> Map.drop([:plan, :description])
      |> Map.merge(%{
        plan: plan,
        flags: flags(detail.countries),
        description: html && :erlang.phash2(html)
      })

    {trip, html}
  end

  defp flags(countries) do
    names = Enum.map(countries, &String.downcase/1)

    Enum.filter(CountryNames.table(), fn {candidate, _code} ->
      candidate = String.downcase(candidate)
      Enum.any?(names, &(String.contains?(&1, candidate) or String.contains?(candidate, &1)))
    end)
  end

  def window(detail, from) do
    case is_binary(from) && Date.from_iso8601(from) do
      {:ok, date} ->
        if Date.compare(date, detail.first_day) != :lt and
             Date.compare(date, detail.last_day) != :gt,
           do: date

      _ ->
        nil
    end
  end

  def previous(detail, days) do
    case days do
      [%{date: date} | _] ->
        if Date.compare(date, detail.first_day) == :gt,
          do:
            Enum.max([Date.add(date, -Dawarich.Trips.DayWindow.limit()), detail.first_day], Date)

      _ ->
        nil
    end
  end
end
