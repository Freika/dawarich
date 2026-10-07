defmodule Dawarich.RailsTimeZone do
  @moduledoc false
  alias Dawarich.TimeZoneName

  @source Path.expand("../../priv/rails_time_zones.json", __DIR__)
  @external_resource @source
  @data @source |> File.read!() |> Jason.decode!()
  @aliases @data["aliases"]
  @zones Map.new(@data["zones"], fn {name, data} ->
           {name, {data["initial"], List.to_tuple(data["transitions"])}}
         end)

  def valid?(name), do: is_binary(name) and not is_nil(canonical(name))

  def format(nil, _settings, _digits), do: nil

  def format(%NaiveDateTime{} = utc, settings, digits),
    do: format(DateTime.from_naive!(utc, "Etc/UTC"), settings, digits)

  def format(%DateTime{} = utc, settings, digits) when digits in [0, 3] do
    zone = resolve(Dawarich.UserTimeZone.zone(settings))
    {initial, transitions} = Map.fetch!(@zones, zone)
    [offset, abbreviation] = period(transitions, DateTime.to_unix(utc), initial)
    local = utc |> DateTime.to_naive() |> NaiveDateTime.add(offset)
    local = %{local | microsecond: {elem(local.microsecond, 0), digits}}
    NaiveDateTime.to_iso8601(local) <> suffix(offset, abbreviation)
  end

  defp resolve(name) do
    name =
      if Dawarich.ReleaseMigrations.Effects.Support.Ruby.present?(name),
        do: name,
        else: System.get_env("TIME_ZONE", "Europe/Berlin")

    canonical(name) || canonical(System.get_env("TIME_ZONE", "UTC")) || "Etc/UTC"
  end

  defp canonical(name) when is_binary(name) do
    name = TimeZoneName.to_iana(name)
    name = Map.get(@aliases, name, name)
    if Map.has_key?(@zones, name), do: name
  end

  defp canonical(_), do: nil

  defp period(transitions, epoch, initial),
    do: search(transitions, epoch, 0, tuple_size(transitions) - 1, initial)

  defp search(_, _, low, high, found) when low > high, do: found

  defp search(transitions, epoch, low, high, found) do
    mid = div(low + high, 2)
    [at, offset, abbreviation] = elem(transitions, mid)

    if at <= epoch,
      do: search(transitions, epoch, mid + 1, high, [offset, abbreviation]),
      else: search(transitions, epoch, low, mid - 1, found)
  end

  defp suffix(0, abbreviation) when abbreviation in ["UTC", "UCT"], do: "Z"

  defp suffix(offset, _abbreviation) do
    sign = if offset < 0, do: "-", else: "+"
    minutes = div(abs(offset), 60)
    sign <> pad(div(minutes, 60)) <> ":" <> pad(rem(minutes, 60))
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
