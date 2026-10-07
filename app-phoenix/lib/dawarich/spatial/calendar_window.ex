defmodule Dawarich.Spatial.CalendarWindow do
  @moduledoc false
  alias Dawarich.{TimeZoneName, UserTimeZone}
  alias Dawarich.Imports.{ImportTime, ZonePeriod}

  def month(actor, date) do
    zone =
      if actor,
        do: DawarichWeb.Api.UserZone.name(actor.timezone || System.get_env("TIME_ZONE", "UTC")),
        else: UserTimeZone.name(%{})

    days(zone, date, Date.end_of_month(date))
  end

  def days(zone, first, last) do
    data = zone |> TimeZoneName.to_iana() |> ZonePeriod.load!()

    {ZonePeriod.resolve(data, NaiveDateTime.new!(first, ~T[00:00:00])),
     ZonePeriod.resolve(data, NaiveDateTime.new!(last, ~T[23:59:59]))}
  end

  def date(value, zone) do
    data = zone |> TimeZoneName.to_iana() |> ZonePeriod.load!()

    case ImportTime.parse(value, data, DateTime.utc_now()) do
      nil ->
        :error

      epoch ->
        {:ok, ZonePeriod.local_now(data, DateTime.from_unix!(epoch)) |> NaiveDateTime.to_date()}
    end
  rescue
    _ -> :error
  end
end
