defmodule Dawarich.Visits.CacheGeneration do
  @moduledoc false

  def bump(repo, user, stamps) do
    {setting, months} = months(repo, user, stamps)
    Dawarich.State.bump_epochs(repo, Enum.map(months, &epoch_key(user.id, &1, setting)))
  end

  def physical_key("timeline_month_summary/" <> rest = key, repo) do
    case Regex.run(~r/\A(\d+)\/(\d{4}-\d{2})\/(.+)\/(?:lite|pro)\/v3\z/, rest) do
      [_, user, month, zone] ->
        case repo.query!(
               "SELECT token FROM phoenix.epochs WHERE key=$1",
               [epoch_key(user, month, zone)],
               log: false
             ).rows do
          [[token]] -> key <> "/" <> token
          [] -> key
        end

      _ ->
        key
    end
  end

  def physical_key(key, _repo), do: key

  def months(repo, user, stamps) do
    setting = Dawarich.UserSettings.get(user)["timezone"] || System.get_env("TIME_ZONE", "UTC")
    setting = if setting == "", do: "UTC", else: setting
    zone = Dawarich.TimeZoneName.to_iana(setting)

    months =
      repo.query!(
        "SELECT DISTINCT to_char(stamp AT TIME ZONE $2, 'YYYY-MM') FROM unnest($1::timestamptz[]) stamp",
        [stamps, zone],
        log: false
      ).rows
      |> List.flatten()

    {setting, months}
  end

  defp epoch_key(user, month, zone), do: "timeline_visit_month/#{user}/#{month}/#{zone}"
end
