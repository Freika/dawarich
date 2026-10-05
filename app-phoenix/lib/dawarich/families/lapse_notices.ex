defmodule Dawarich.Families.LapseNotices do
  @moduledoc false

  alias Dawarich.{RailsCommands, RailsTime, TimeZoneName}
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  def notified?(settings),
    do: Ruby.present?(get_in(settings, ["family", "plan_lapse_notified_at"]))

  def clear(repo, user_id, settings, now) do
    if notified?(settings) do
      repo.query!(
        "UPDATE users SET settings = jsonb_set(COALESCE(settings, '{}'::jsonb), '{family}', " <>
          "COALESCE(settings->'family', '{}'::jsonb) - 'plan_lapse_notified_at'), updated_at = $2 WHERE id = $1",
        [user_id, DateTime.to_naive(now)],
        log: false
      )
    end
  end

  def lapse(repo, user_id, family_id, settings, period, now, owner, opts) do
    unless notified?(settings) do
      if Keyword.get(opts, :notify, true) do
        payload = %{
          "user_id" => user_id,
          "family_id" => family_id,
          "locale" => Keyword.get(opts, :locale, "en"),
          "lapse_at" => lapse_at(period)
        }

        publish(repo, owner, payload, now)
      else
        mark(
          repo,
          user_id,
          now,
          Keyword.get(opts, :time_zone, System.get_env("TIME_ZONE", "Europe/Berlin"))
        )
      end
    end
  end

  def publish(repo, :sidekiq, payload, _now),
    do: RailsCommands.insert!(repo, "mail.family_lapse", payload)

  def publish(repo, :oban, payload, now) do
    dedupe = "family-lapse:#{payload["family_id"]}:#{payload["user_id"]}:#{payload["lapse_at"]}"

    repo.query!(
      "INSERT INTO public.job_outbox (event_id, command_type, command_version, payload, aggregate_id, dedupe_key, scheduled_at, metadata) " <>
        "VALUES ($1, 'mail.family_lapse', 1, $2, $3, $4, $5, $6) " <>
        "ON CONFLICT (command_type, dedupe_key) WHERE state = 'pending' AND dedupe_key IS NOT NULL DO NOTHING",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        payload,
        payload["user_id"],
        dedupe,
        now,
        %{"producer" => "Families::SyncMembers"}
      ],
      log: false
    )
  end

  defp mark(repo, user_id, now, zone) do
    marked =
      RailsTime.with_zone(repo, TimeZoneName.to_iana(zone), fn ->
        [[text]] =
          repo.query!("SELECT " <> RailsTime.sql("$1::timestamp", 0), [DateTime.to_naive(now)],
            log: false
          ).rows

        String.replace_suffix(text, "Z", "+00:00")
      end)

    repo.query!(
      "UPDATE users SET settings = jsonb_set(jsonb_set(COALESCE(settings, '{}'::jsonb), '{family}', " <>
        "COALESCE(settings->'family', '{}'::jsonb), true), '{family,plan_lapse_notified_at}', to_jsonb($2::text), true), updated_at = $3 WHERE id = $1",
      [user_id, marked, DateTime.to_naive(now)],
      log: false
    )
  end

  defp lapse_at(nil), do: "none"

  defp lapse_at(period),
    do:
      period
      |> DateTime.from_naive!("Etc/UTC")
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()
end
