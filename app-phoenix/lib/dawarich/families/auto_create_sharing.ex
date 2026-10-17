defmodule Dawarich.Families.AutoCreateSharing do
  @moduledoc false

  alias Dawarich.{RailsTime, TimeZoneName}
  alias Dawarich.Families.Clock
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def enable(repo, settings, now, zone) do
    RailsTime.with_zone(repo, TimeZoneName.to_iana(zone), fn ->
      transform(repo, Dawarich.UserSettings.provided(settings), now)
    end)
  end

  defp transform(repo, settings, now) do
    family = settings["family"] || %{}
    old = family["location_sharing"] || %{}
    history = old["share_history"] || false

    config = %{
      "enabled" => true,
      "started_at" => old["started_at"] || iso(repo, DateTime.to_naive(now)),
      "share_history" => history,
      "history_before_sharing" => history && old["history_before_sharing"] == true,
      "history_window" =>
        if(old["history_window"] in ~w(24h 7d 30d all), do: old["history_window"], else: "7d")
    }

    config = if Ruby.present?(old["duration"]), do: duration(repo, config, old, now), else: config
    Map.put(settings, "family", Map.put(family, "location_sharing", config))
  end

  defp duration(repo, config, old, now) do
    config = Map.put(config, "duration", old["duration"])
    expiry = carried(old, now)
    if expiry, do: Map.put(config, "expires_at", iso(repo, expiry)), else: config
  end

  defp carried(old, now) do
    if Ruby.present?(old["expires_at"]) do
      parsed = parse(old["expires_at"])

      if parsed && NaiveDateTime.compare(parsed, DateTime.to_naive(now)) == :gt,
        do: parsed,
        else: expiry(old["duration"], now)
    end
  end

  defp parse(text) do
    Clock.parse(text)
  rescue
    ArgumentError -> nil
  end

  defp expiry(duration, now) do
    hours =
      case Integer.parse(duration |> to_string() |> String.trim_leading()) do
        {hours, _} when hours > 0 -> hours
        _ -> nil
      end

    if hours, do: NaiveDateTime.add(DateTime.to_naive(now), hours * 3600)
  end

  defp iso(repo, at) do
    [[text]] = repo.query!("SELECT " <> RailsTime.sql("$1::timestamp", 0), [at], log: false).rows
    String.replace_suffix(text, "Z", "+00:00")
  end
end
