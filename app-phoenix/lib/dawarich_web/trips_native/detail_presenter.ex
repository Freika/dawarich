defmodule DawarichWeb.TripsNative.DetailPresenter do
  @moduledoc false

  alias Dawarich.{CountryNames, TripDescription}
  alias DawarichWeb.TripPlanItems

  def present(detail, scope) do
    plan =
      if detail.plan && TripPlanItems.visible?(detail.plan),
        do: TripPlanItems.prepare(detail.plan, Dawarich.UserSettings.get(scope.user))

    detail
    |> Map.drop([:plan])
    |> Map.merge(%{
      plan: plan,
      flags: CountryNames.table(),
      description_html: description(detail.description)
    })
  end

  defp description(html) when is_binary(html),
    do: html |> TripDescription.html() |> IO.iodata_to_binary()

  defp description(_html), do: nil

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
