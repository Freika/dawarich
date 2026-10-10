defmodule Dawarich.Cable.TurboEvents do
  @moduledoc false

  alias Dawarich.{Cable, Notifications}
  alias DawarichWeb.CableTurbo

  @batch 100
  @claim_notification """
  DELETE FROM phoenix.notification_events WHERE id = (
    SELECT id FROM phoenix.notification_events ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
  RETURNING notification_id
  """
  @claim_trip """
  DELETE FROM phoenix.trip_events WHERE id = (
    SELECT id FROM phoenix.trip_events ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED)
  RETURNING id, trip_id, kind, failed
  """
  @notification """
  SELECT n.id, n.user_id, n.title, n.kind,
         (SELECT count(*) FROM notifications u WHERE u.user_id = n.user_id AND u.read_at IS NULL)
  FROM notifications n JOIN users usr ON usr.id = n.user_id AND usr.deleted_at IS NULL
  WHERE n.id = $1
  """
  @trip "SELECT coalesce(last_recalculated_at > $2::timestamp - interval '60 seconds', false) FROM trips WHERE id = $1"

  def drain(jobs_repo, repo), do: notifications(jobs_repo, repo) + trips(jobs_repo, repo)

  def notifications(jobs_repo, repo),
    do: each_event(jobs_repo, @claim_notification, &notify(repo, &1, jobs_repo), 0)

  def trips(jobs_repo, repo, now \\ NaiveDateTime.utc_now()),
    do: each_event(jobs_repo, @claim_trip, &trip(repo, &1, now, jobs_repo), 0)

  defp each_event(_jobs_repo, _claim, _publish, @batch), do: @batch

  defp each_event(jobs_repo, claim, publish, done) do
    {:ok, claimed?} =
      jobs_repo.transaction(fn ->
        case jobs_repo.query!(claim, [], log: false).rows do
          [event] ->
            publish.(event)
            true

          [] ->
            false
        end
      end)

    if claimed?, do: each_event(jobs_repo, claim, publish, done + 1), else: done
  end

  defp notify(repo, [notification_id], jobs_repo) do
    for [id, user_id, title, kind, unread] <-
          repo.query!(@notification, [notification_id], log: false).rows do
      item = %{id: id, title: title, kind: Notifications.kind_name(kind)}
      stream = [{:user, user_id}, "notifications"]

      :ok =
        Cable.turbo(stream, "prepend", "notifications-list", CableTurbo.navbar_item(item),
          repo: jobs_repo
        )

      :ok =
        Cable.turbo(stream, "replace", "notifications-badge", CableTurbo.badge(unread),
          repo: jobs_repo
        )
    end
  end

  defp trip(repo, [_id, trip_id, "path", _failed], now, jobs_repo) do
    if recalculating(repo, trip_id, now) != nil,
      do: :ok = Cable.refresh([{:trip, trip_id}], repo: jobs_repo)
  end

  defp trip(repo, [_id, trip_id, "finished", failed], now, jobs_repo) do
    case recalculating(repo, trip_id, now) do
      nil ->
        :ok

      busy ->
        html = CableTurbo.recalculate_button(trip_id, busy, failed)

        :ok =
          Cable.turbo([{:trip, trip_id}], "replace", "trip_recalculate_frame", html,
            repo: jobs_repo
          )
    end
  end

  defp trip(_repo, _event, _now, _jobs_repo), do: :ok

  defp recalculating(repo, trip_id, now) do
    case repo.query!(@trip, [trip_id, now], log: false).rows do
      [[busy]] -> busy
      [] -> nil
    end
  end
end
