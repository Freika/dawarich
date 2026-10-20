defmodule DawarichWeb.TripsNative.FormPreview do
  @moduledoc false

  def config(trip, values, user, locale) do
    base = %{"interactive" => true, "styleName" => trip.style, "locale" => locale}

    range = if trip.id && same_dates?(trip, values), do: :original, else: range(values, user)

    case range do
      {:ok, first, last} -> Map.put(base, "range", %{"startAt" => first, "endAt" => last})
      _ -> if trip.id, do: Map.put(base, "tripId", trip.id), else: base
    end
  end

  defp same_dates?(trip, values),
    do:
      Map.take(trip.values, ~w(started_at ended_at)) == Map.take(values, ~w(started_at ended_at))

  defp range(values, user) do
    zone = Dawarich.UserTimeZone.zone(Dawarich.UserSettings.get(user))
    zone = if zone in [nil, ""], do: System.get_env("TIME_ZONE", "UTC"), else: zone
    zone = Dawarich.TimeZoneName.to_iana(zone)

    with {:ok, first} <- stamp(values["started_at"], zone),
         {:ok, last} <- stamp(values["ended_at"], zone),
         true <- first < last,
         do: {:ok, first, last}
  end

  defp stamp(value, zone) when is_binary(value) and byte_size(value) == 16 do
    with {:ok, naive} <- NaiveDateTime.from_iso8601(value <> ":00") do
      {:ok,
       naive
       |> Dawarich.MapWindow.local_utc(zone)
       |> DateTime.from_naive!("Etc/UTC")
       |> DateTime.to_iso8601()}
    end
  end

  defp stamp(_, _), do: :error
end
