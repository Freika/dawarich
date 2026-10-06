defmodule Dawarich.Settings.General do
  @moduledoc false
  alias Dawarich.{Stats.Schedule, TimeZoneName, TimeZoneOptions, UserSettings}

  @boolean ~w(monthly_digest_emails_enabled yearly_digest_emails_enabled news_emails_enabled show_supporter_badge)

  def save(repo, id, params, opts \\ []) do
    repo.transaction(
      fn ->
        case repo.query!(
               "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
               [id],
               log: false
             ).rows do
          [[%{} = previous]] ->
            settings = changes(previous, params)

            if settings != previous do
              repo.query!(
                "UPDATE users SET settings=$2, updated_at=$3 WHERE id=$1",
                [id, settings, NaiveDateTime.utc_now()],
                log: false
              )

              if settings["timezone"] != previous["timezone"], do: rebucket(repo, id, opts)
            end

            settings

          _ ->
            repo.rollback(:invalid_settings)
        end
      end,
      mode: :savepoint
    )
  rescue
    _ -> {:error, :save_failed}
  end

  defp changes(previous, params) do
    changes = Map.take(params, ~w(supporter_email supporter_github_username))

    changes =
      if params["locale"] in DawarichWeb.Locale.locales(),
        do: Map.put(changes, "locale", params["locale"]),
        else: changes

    zone = params["timezone"]

    changes =
      if is_binary(zone) and
           Enum.any?(TimeZoneOptions.list(), fn {_, iana} ->
             iana == TimeZoneName.to_iana(zone)
           end),
         do: Map.put(changes, "timezone", zone),
         else: changes

    changes =
      Enum.reduce(@boolean, changes, fn key, acc ->
        if Map.has_key?(params, key),
          do: Map.put(acc, key, UserSettings.cast(params[key])),
          else: acc
      end)

    settings = Map.merge(previous, changes)

    if Enum.any?(
         ~w(monthly_digest_emails_enabled yearly_digest_emails_enabled),
         &Map.has_key?(params, &1)
       ),
       do: Map.delete(settings, "digest_emails_enabled"),
       else: settings
  end

  defp rebucket(repo, id, opts) do
    months =
      repo.query!(
        "UPDATE stats SET calculation_version=0, repair_deferred_at=$2 WHERE user_id=$1 RETURNING year, month",
        [id, NaiveDateTime.utc_now()],
        log: false
      ).rows

    for [year, month] <- months, do: Schedule.calculate(repo, id, year, month, false, opts)
  end
end
