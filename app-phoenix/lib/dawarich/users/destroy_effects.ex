defmodule Dawarich.Users.DestroyEffects do
  @moduledoc false
  alias Dawarich.Users.DestructionWebhookWorker

  @attachments [
    {"Import", "imports"},
    {"Export", "exports"},
    {"Points::RawDataArchive", "points_raw_data_archives"},
    {"Poster", "posters"},
    {"RouteVideo", "route_videos"}
  ]
  @mail ~w(users.explore_features_mail mail.family_lapse mail.user.welcome mail.user.archival_approaching mail.user.oauth_account_link mail.user.account_destroy_confirmation)
  @direct ~w(imports stats exports posters route_videos notifications achievement_progresses user_achievements flights notes service_settings)
  @planned ~w(planned_reservations planned_accommodations planned_travellers planned_unplanned_places)

  def call(repo, id) do
    case repo.query!(
           "SELECT email FROM users WHERE id=$1 AND deleted_at IS NOT NULL FOR UPDATE",
           [id],
           log: false
         ).rows do
      [] ->
        :ok

      [[email]] ->
        case family_guard(repo, id) do
          :ok ->
            snapshot!(repo, id, email)
            attachments!(repo, id)
            cleanup!(repo, id)
            :ok

          blocked ->
            blocked
        end
    end
  end

  def clear_cache(id) do
    keys =
      for suffix <- ~w(countries_visited cities_visited total_distance years_tracked),
          do: "dawarich/user_#{id}_#{suffix}"

    Dawarich.Redis.cache_command(["DEL" | keys ++ Enum.map(keys, &("phoenix/" <> &1))])
    :ok
  end

  defp snapshot!(repo, id, email) do
    repo.insert!(
      DestructionWebhookWorker.new(%{
        "user_id" => id,
        "email" => email,
        "event_id" => Ecto.UUID.generate()
      }),
      prefix: "oban"
    )
  end

  defp family_guard(repo, id) do
    families =
      repo.query!("SELECT id FROM families WHERE creator_id=$1 ORDER BY id FOR UPDATE", [id],
        log: false
      ).rows
      |> List.flatten()

    [[blocked]] =
      repo.query!(
        "SELECT EXISTS(SELECT 1 FROM family_memberships WHERE family_id=ANY($1::bigint[]) GROUP BY family_id HAVING count(*)>1)",
        [families],
        log: false
      ).rows

    if blocked, do: {:cancel, "account deletion blocked by family members"}, else: :ok
  end

  defp attachments!(repo, id) do
    blobs =
      Enum.flat_map(@attachments, fn {type, table} ->
        repo.query!(
          "DELETE FROM active_storage_attachments WHERE record_type=$1 AND record_id IN(SELECT id FROM #{table} WHERE user_id=$2) RETURNING blob_id",
          [type, id],
          log: false
        ).rows
        |> List.flatten()
      end)

    rich =
      repo.query!(
        "SELECT id FROM action_text_rich_texts WHERE record_type='Trip' AND record_id IN(SELECT id FROM trips WHERE user_id=$1)",
        [id],
        log: false
      ).rows
      |> List.flatten()

    blobs =
      blobs ++
        (repo.query!(
           "DELETE FROM active_storage_attachments WHERE record_type='ActionText::RichText' AND record_id=ANY($1::bigint[]) RETURNING blob_id",
           [rich],
           log: false
         ).rows
         |> List.flatten())

    Dawarich.Exports.PurgeWorker.enqueue!(repo, Enum.uniq(blobs) |> Enum.sort())
  end

  defp cleanup!(repo, id) do
    repo.query!(
      "DELETE FROM job_outbox WHERE aggregate_id=$1 AND state='pending' AND command_type=ANY($2)",
      [id, @mail],
      log: false
    )

    repo.query!(
      "UPDATE oban.oban_jobs SET state='cancelled',cancelled_at=now() WHERE state='scheduled' AND args->>'user_id'=$1 AND worker=ANY($2)",
      [to_string(id), scheduled_workers()],
      log: false
    )

    repo.query!("DELETE FROM points WHERE user_id=$1", [id], log: false)
    for table <- @direct, do: delete_user!(repo, table, id)

    repo.query!(
      "DELETE FROM place_visits WHERE visit_id IN(SELECT id FROM visits WHERE user_id=$1) OR place_id IN(SELECT id FROM places WHERE user_id=$1)",
      [id],
      log: false
    )

    delete_user!(repo, "visits", id)
    delete_user!(repo, "areas", id)

    repo.query!(
      "UPDATE visits SET place_id=NULL WHERE place_id IN(SELECT id FROM places WHERE user_id=$1)",
      [id],
      log: false
    )

    delete_user!(repo, "places", id)

    repo.query!(
      "DELETE FROM taggings WHERE tag_id IN(SELECT id FROM tags WHERE user_id=$1)",
      [id],
      log: false
    )

    delete_user!(repo, "tags", id)
    trips!(repo, id)
    delete_user!(repo, "trip_sources", id)

    repo.query!(
      "DELETE FROM track_segments WHERE track_id IN(SELECT id FROM tracks WHERE user_id=$1)",
      [id],
      log: false
    )

    if repo.query!("SELECT to_regclass('public.video_exports') IS NOT NULL", [], log: false).rows ==
         [[true]],
       do: delete_user!(repo, "video_exports", id)

    delete_user!(repo, "tracks", id)
    delete_user!(repo, "points_raw_data_archives", id)
    delete_user!(repo, "digests", id)

    repo.query!(
      "DELETE FROM family_invitations WHERE invited_by_id=$1",
      [id],
      log: false
    )

    repo.query!(
      "DELETE FROM family_location_requests WHERE requester_id=$1 OR target_user_id=$1 OR family_id IN(SELECT id FROM families WHERE creator_id=$1)",
      [id],
      log: false
    )

    repo.query!(
      "DELETE FROM family_memberships WHERE user_id=$1 OR family_id IN(SELECT id FROM families WHERE creator_id=$1)",
      [id],
      log: false
    )

    repo.query!("DELETE FROM families WHERE creator_id=$1", [id], log: false)
    repo.query!("DELETE FROM phoenix.stats_point_counts WHERE user_id=$1", [id], log: false)
    repo.query!("DELETE FROM users WHERE id=$1", [id], log: false)
  end

  defp trips!(repo, id) do
    days = "SELECT id FROM planned_days WHERE trip_id IN(SELECT id FROM trips WHERE user_id=$1)"

    repo.query!(
      "UPDATE planned_reservations SET planned_day_id=NULL WHERE planned_day_id IN(#{days})",
      [id],
      log: false
    )

    for table <- ~w(planned_day_notes planned_stops),
        do: repo.query!("DELETE FROM #{table} WHERE planned_day_id IN(#{days})", [id], log: false)

    for table <- ["planned_days" | @planned],
        do:
          repo.query!(
            "DELETE FROM #{table} WHERE trip_id IN(SELECT id FROM trips WHERE user_id=$1)",
            [id],
            log: false
          )

    repo.query!(
      "DELETE FROM notes WHERE attachable_type='Trip' AND attachable_id IN(SELECT id FROM trips WHERE user_id=$1)",
      [id],
      log: false
    )

    repo.query!(
      "DELETE FROM action_text_rich_texts WHERE record_type='Trip' AND record_id IN(SELECT id FROM trips WHERE user_id=$1)",
      [id],
      log: false
    )

    repo.query!(
      "DELETE FROM shared_links WHERE resource_type=0 AND resource_id IN(SELECT id FROM trips WHERE user_id=$1)",
      [id],
      log: false
    )

    delete_user!(repo, "trips", id)
  end

  defp delete_user!(repo, table, id),
    do: repo.query!("DELETE FROM #{table} WHERE user_id=$1", [id], log: false)

  defp scheduled_workers do
    ~w(Dawarich.Mail.WelcomeWorker Dawarich.Mail.ArchivalApproachingWorker Dawarich.Mail.OauthAccountLinkWorker Dawarich.Mail.AccountDestroyConfirmationWorker Dawarich.Mail.Digests.MonthlyWorker Dawarich.Mail.Digests.YearlyWorker Dawarich.Mail.Digests.DeliveryWorker Dawarich.Tracks.RealtimeWorker Dawarich.Tracks.BoundaryWorker)
  end
end
