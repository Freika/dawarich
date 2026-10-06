defmodule Dawarich.Imports.DestroyNativeEffects do
  @moduledoc false
  alias Dawarich.Imports.Postprocessing.Native

  def selected?(repo, "imports.destroy_callbacks", %{"step" => step}) do
    type =
      if step == "places_cleanup",
        do: "places.delete_if_orphan",
        else: "transportation.reclassify_track"

    Native.selected?(repo, type)
  end

  def selected?(repo, "imports.destroy_achievements", _),
    do: Native.selected?(repo, "achievements.check")

  def selected?(repo, "imports.destroy_stats", _),
    do: Native.selected?(repo, "stats.calculate_month")

  def selected?(repo, _, _), do: Native.selected?(repo, "imports.destroy")

  def run!(repo, user, _id, event, "imports.destroy_callbacks", %{
        "step" => "places_cleanup",
        "place_ids" => ids
      }) do
    rows =
      repo.query!(
        "SELECT id FROM places WHERE id=ANY($1) AND user_id=$2 ORDER BY id",
        [ids, user],
        log: false
      ).rows

    for [place] <- rows,
        do:
          Native.publish!(
            repo,
            Dawarich.Places.DeleteIfOrphanWorker,
            %{"user_id" => user, "place_id" => place},
            event,
            DateTime.utc_now()
          )

    :ok
  end

  def run!(repo, user, _id, event, "imports.destroy_callbacks", %{
        "step" => "reclassify_tracks",
        "track_ids" => ids
      }) do
    rows =
      repo.query!(
        "SELECT id FROM tracks WHERE id=ANY($1) AND user_id=$2 ORDER BY id",
        [ids, user],
        log: false
      ).rows

    for [track] <- rows,
        do:
          Native.publish!(
            repo,
            Dawarich.Transportation.ReclassifyTrackWorker,
            %{"track_id" => track, "report_progress" => false, "user_id" => nil},
            event,
            DateTime.utc_now()
          )

    :ok
  end

  def run!(repo, user, _id, event, "imports.destroy_achievements", payload),
    do:
      Dawarich.Imports.ImportsDestroyAchievementsEffects.enqueue!(
        repo,
        user,
        payload["oldest_timestamp"],
        event
      )

  def run!(repo, user, id, event, "imports.destroy_stats", _) do
    [[context]] =
      repo.query!(
        "SELECT context FROM phoenix.import_destroy_runs WHERE import_id=$1 AND user_id=$2",
        [id, user],
        log: false
      ).rows

    [[settings]] = repo.query!("SELECT settings FROM users WHERE id=$1", [user], log: false).rows

    zone =
      Dawarich.TimeZoneName.to_iana(
        context["time_zone"] || Dawarich.UserTimeZone.name(settings, repo)
      )

    months =
      repo.query!(
        "SELECT year,month FROM stats WHERE user_id=$1 UNION SELECT DISTINCT extract(year FROM to_timestamp(timestamp) AT TIME ZONE $2)::int,extract(month FROM to_timestamp(timestamp) AT TIME ZONE $2)::int FROM points WHERE user_id=$1",
        [user, zone],
        log: false
      ).rows

    for [year, month] <- Enum.uniq(months ++ (context["months"] || [])) do
      Native.publish!(
        repo,
        Dawarich.Stats.CalculateMonthWorker,
        %{"user_id" => user, "year" => year, "month" => month, "notify_on_failure" => true},
        event,
        DateTime.utc_now()
      )
    end

    :ok
  end

  def run!(_repo, _user, _id, _event, kind, _)
      when kind in ["imports.destroy_status", "imports.destroy_complete"],
      do: :ok
end
