defmodule Dawarich.Lite.ArchivalWarnings do
  @moduledoc false
  require Logger

  alias Dawarich.I18n
  alias Dawarich.Mail.{ArchivalApproachingWorker, ExploreFeatures}
  alias Dawarich.Notifications
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @lock_user "SELECT settings FROM users WHERE id = $1 AND plan = 0 AND deleted_at IS NULL FOR UPDATE"

  @facts """
  SELECT (SELECT min(p.timestamp) FROM points p WHERE p.user_id = $1),
    EXISTS (
      SELECT 1 FROM family_memberships m JOIN families f ON f.id = m.family_id
      LEFT JOIN users o ON o.id = f.creator_id AND o.deleted_at IS NULL
      WHERE m.user_id = $1 AND (
        (f.access_until IS NOT NULL AND f.access_until > (now() AT TIME ZONE 'UTC'))
        OR (f.access_until IS NULL AND o.plan = 2 AND o.active_until > (now() AT TIME ZONE 'UTC'))))
  """

  @zone "SELECT set_config('TimeZone', $1, true)"

  @cutoffs """
  SELECT
    floor(extract(epoch from ($2::timestamptz AT TIME ZONE $1 - interval '11 months') AT TIME ZONE $1))::bigint,
    floor(extract(epoch from ($2::timestamptz AT TIME ZONE $1 - interval '11 months 15 days') AT TIME ZONE $1))::bigint,
    floor(extract(epoch from ($2::timestamptz AT TIME ZONE $1 - interval '12 months') AT TIME ZONE $1))::bigint,
    to_char($2::timestamptz, 'YYYY-MM-DD"T"HH24:MI:SS') ||
      CASE WHEN to_char($2::timestamptz, 'TZ') IN ('UTC', 'UCT') THEN 'Z' ELSE to_char($2::timestamptz, 'TZH:TZM') END
  """

  @mark """
  UPDATE users SET settings = COALESCE(settings, '{}'::jsonb) ||
    jsonb_build_object('archival_warnings', COALESCE(settings->'archival_warnings', '{}'::jsonb) || $2::jsonb)
  WHERE id = $1 AND NOT (COALESCE(settings->'archival_warnings', '{}'::jsonb) ? $3)
  RETURNING id
  """

  @notices %{
    approaching:
      {"your_oldest_data_will_archive_in_30_days",
       "your_oldest_month_of_location_data_will_be_archived_soon"},
    archived: {"data_has_been_archived", "month_of_location_data_has_been_archived_your_archived"}
  }

  def check_user(repo, tz, user_id, mail_owned?, oban, now \\ DateTime.utc_now()) do
    with [[settings]] <- query(repo, @lock_user, [user_id]),
         [[oldest, false]] when is_integer(oldest) <- query(repo, @facts, [user_id]),
         {c11, c11_5, c12, marked_at} <- cutoffs(repo, tz, now),
         thresholds = [
           {"11mo", c11, :approaching},
           {"11_5mo", c11_5, :email},
           {"12mo", c12, :archived}
         ],
         [_ | _] = crossed <- crossed(thresholds, oldest, warnings(settings)),
         {key, _cutoff, action} = List.last(crossed),
         true <- mail_allowed?(action, mail_owned?, user_id),
         marks = Map.new(crossed, fn {crossed_key, _, _} -> {crossed_key, marked_at} end),
         [[_]] <- query(repo, @mark, [user_id, marks, key]) do
      effect(repo, oban, user_id, action, ExploreFeatures.locale(settings, nil), marked_at)
    else
      _ -> :skip
    end
  end

  def cutoffs(repo, tz, now) do
    query(repo, @zone, [tz])
    [[c11, c11_5, c12, marked_at]] = query(repo, @cutoffs, [tz, now])
    {c11, c11_5, c12, marked_at}
  end

  defp crossed(thresholds, oldest, warnings),
    do:
      Enum.filter(thresholds, fn {key, cutoff, _action} ->
        oldest <= cutoff and Ruby.blank?(warnings[key])
      end)

  defp warnings(settings) do
    case Dawarich.UserSettings.safe(settings) do
      %{"archival_warnings" => %{} = warnings} -> warnings
      _settings -> %{}
    end
  end

  defp mail_allowed?(:email, false, user_id) do
    Logger.warning("[lite.archival] mail key owned by sidekiq; user #{user_id} skipped")
    false
  end

  defp mail_allowed?(_action, _mail_owned?, _user_id), do: true

  defp effect(_repo, oban, user_id, :email, locale, marked_at) do
    args = %{
      "event_id" => Ecto.UUID.generate(),
      "user_id" => user_id,
      "locale" => locale,
      "epoch" => marked_at
    }

    Oban.insert!(oban, ArchivalApproachingWorker.new(args))
    :mailed
  end

  defp effect(repo, _oban, user_id, action, locale, _marked_at) do
    {title, content} = Map.fetch!(@notices, action)
    Notifications.create!(repo, user_id, :warning, text!(locale, title), text!(locale, content))
    :notified
  end

  defp text!(locale, key) do
    {:ok, text} = I18n.t(locale, "jobs.lite.archival_warning_job." <> key)
    text
  end

  defp query(repo, sql, params), do: repo.query!(sql, params, log: false).rows
end
