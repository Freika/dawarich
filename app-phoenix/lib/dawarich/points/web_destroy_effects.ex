defmodule Dawarich.Points.WebDestroyEffects do
  @moduledoc false
  alias Dawarich.{RailsCommands, RailsEffects, UserTimeZone}
  alias Dawarich.Jobs.Ownership

  @types ~w(achievements.check stats.calculate_month tracks.recalculate)
  def publish!(repo, user, deleted, ctx) do
    owners = Enum.map(@types, &Ownership.lock(repo, "command:" <> &1))
    stamps = Enum.map(deleted, & &1.timestamp)
    tracks = deleted |> Enum.map(& &1.track_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    zone = Map.get_lazy(ctx, :timezone, fn -> UserTimeZone.iana(repo, user.settings) end)

    if Enum.all?(owners, &(&1 == :oban)) do
      now = Map.get_lazy(ctx, :now, &DateTime.utc_now/0)

      metadata = %{
        "producer" => "Phoenix PointDelete",
        "locale" => ctx.locale,
        "time_zone" => zone,
        "request_event_id" => Ecto.UUID.generate()
      }

      RailsEffects.tile_epoch(repo, user.id, stamps)

      months =
        repo.query!(
          "SELECT DISTINCT extract(year FROM to_timestamp(at) AT TIME ZONE $2)::int,extract(month FROM to_timestamp(at) AT TIME ZONE $2)::int FROM unnest($1::bigint[]) AS t(at) ORDER BY 1,2",
          [stamps, zone]
        ).rows

      for [year, month] <- months do
        insert!(
          repo,
          "stats.calculate_month",
          %{"user_id" => user.id, "year" => year, "month" => month, "notify_on_failure" => true},
          user.id,
          nil,
          now,
          metadata
        )
      end

      for track <- tracks,
          do:
            insert!(repo, "tracks.recalculate", %{"track_id" => track}, track, nil, now, metadata)

      insert!(
        repo,
        "achievements.check",
        %{"user_id" => user.id, "notify" => true, "oldest_timestamp" => Enum.min(stamps)},
        user.id,
        "point-delete:#{user.id}",
        DateTime.add(now, 60),
        metadata
      )
    else
      RailsCommands.insert!(repo, "points.web_destroy_follow_up", %{
        "user_id" => user.id,
        "timestamps" => stamps,
        "track_ids" => tracks,
        "oldest_timestamp" => Enum.min(stamps),
        "locale" => ctx.locale,
        "timezone" => zone
      })
    end
  end

  defp insert!(repo, kind, payload, aggregate, dedupe, now, metadata) do
    repo.query!(
      "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6,$7) ON CONFLICT(command_type,dedupe_key) WHERE state='pending' AND dedupe_key IS NOT NULL DO UPDATE SET payload=jsonb_set(job_outbox.payload,'{oldest_timestamp}',to_jsonb(LEAST((job_outbox.payload->>'oldest_timestamp')::bigint,($3->>'oldest_timestamp')::bigint)))",
      [Ecto.UUID.bingenerate(), kind, payload, metadata, aggregate, dedupe, now]
    )
  end
end
