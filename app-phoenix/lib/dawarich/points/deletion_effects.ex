defmodule Dawarich.Points.DeletionEffects do
  @moduledoc false
  alias Dawarich.Points.NativeEffects

  def publish(repo, user, deleted, ctx) do
    stamps = Enum.map(deleted, & &1.timestamp)

    zone =
      Map.get_lazy(ctx, :timezone, fn ->
        Dawarich.UserTimeZone.iana(repo, Dawarich.UserSettings.get(user))
      end)

    now = Map.get_lazy(ctx, :now, &DateTime.utc_now/0)
    Dawarich.RailsEffects.tile_epoch(repo, user.id, stamps)

    months =
      repo.query!(
        "SELECT DISTINCT extract(year FROM to_timestamp(at) AT TIME ZONE $2)::int,extract(month FROM to_timestamp(at) AT TIME ZONE $2)::int FROM unnest($1::bigint[]) AS t(at) ORDER BY 1,2",
        [stamps, zone],
        log: false
      ).rows

    for [year, month] <- months do
      NativeEffects.enqueue(repo, Dawarich.Points.AnomalyStatsWorker, %{
        "user_id" => user.id,
        "year" => year,
        "month" => month,
        "time_zone" => zone,
        "notify_on_failure" => true
      })
    end

    tracks = deleted |> Enum.map(& &1.track_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    for track <- tracks,
        do: NativeEffects.enqueue(repo, Dawarich.Tracks.RecalculateWorker, %{"track_id" => track})

    achievements(repo, user.id, Enum.min(stamps), now)
    :ok
  end

  defp achievements(repo, user, oldest, now) do
    repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [user], log: false)

    pending =
      repo.query!(
        "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker' AND args->>'user_id'=$1 AND state IN ('available','scheduled') AND tags @> ARRAY['point-delete']::text[] ORDER BY id FOR UPDATE",
        [to_string(user)],
        log: false
      ).rows

    case pending do
      [] ->
        NativeEffects.enqueue(
          repo,
          Dawarich.Achievements.CheckWorker,
          %{"user_id" => user, "notify" => true, "oldest_timestamp" => oldest},
          scheduled_at: DateTime.add(now, 60),
          tags: ["point-delete"]
        )

      ids ->
        repo.query!(
          "UPDATE oban.oban_jobs SET args=jsonb_set(args,'{oldest_timestamp}',to_jsonb(LEAST((args->>'oldest_timestamp')::bigint,$2::bigint))) WHERE id=ANY($1::bigint[])",
          [List.flatten(ids), oldest],
          log: false
        )
    end
  end
end
