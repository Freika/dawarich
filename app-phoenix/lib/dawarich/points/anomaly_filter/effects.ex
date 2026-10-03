defmodule Dawarich.Points.AnomalyFilter.Effects do
  @moduledoc false
  alias Dawarich.RailsCommands
  alias Dawarich.Jobs.Ownership

  @pending_ttl 259_200
  @defer """
  INSERT INTO phoenix.achievement_checks AS c (user_id, oldest_timestamp, revision, expires_at)
  VALUES ($1, $2, nextval('phoenix.achievement_check_revisions'), statement_timestamp() + make_interval(secs => $3))
  ON CONFLICT (user_id) DO UPDATE SET
    oldest_timestamp = CASE WHEN c.expires_at <= statement_timestamp() THEN EXCLUDED.oldest_timestamp
                            ELSE LEAST(c.oldest_timestamp, EXCLUDED.oldest_timestamp) END,
    revision = nextval('phoenix.achievement_check_revisions'),
    expires_at = EXCLUDED.expires_at
  """

  def call(_context, [], _opts), do: :ok

  def call(context, flagged, opts) do
    timestamps =
      flagged
      |> Enum.map(fn [_id, _track, at] -> at end)
      |> Enum.uniq_by(fn at -> DateTime.from_unix!(at).year |> max(1970) |> min(2100) end)

    context.fence.(fn ->
      RailsCommands.insert!(context.repo, "points.tile_epoch", %{
        "user_id" => context.user_id,
        "timestamps" => timestamps
      })
    end)

    if Keyword.get(opts, :invalidate_dependents, true) do
      defer(context, flagged)

      queue =
        case Keyword.get(opts, :job_queue) do
          nil -> nil
          queue -> to_string(queue)
        end

      flagged
      |> Enum.map(fn [_id, track, _at] -> track end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.each(&track(context, &1, queue))

      months(context, flagged)
      |> Enum.each(fn [year, month] ->
        context.fence.(fn ->
          RailsCommands.insert!(context.repo, "points.anomaly_stats", %{
            "user_id" => context.user_id,
            "year" => year,
            "month" => month,
            "job_queue" => queue,
            "time_zone" => context.zone
          })
        end)
      end)
    end

    :ok
  end

  defp defer(context, flagged) do
    oldest = flagged |> Enum.map(fn [_id, _track, at] -> at end) |> Enum.min()

    context.fence.(fn ->
      context.repo.query!(@defer, [context.user_id, oldest, @pending_ttl], log: false)
    end)
  end

  defp track(context, track, queue) do
    payload = %{"user_id" => context.user_id, "track_id" => track, "job_queue" => queue}

    context.fence.(fn ->
      {:ok, :ok} =
        context.repo.transaction(fn ->
          case Ownership.lock(context.repo, "command:tracks.recalculate") do
            :oban -> insert_track!(context.repo, payload, track)
            :sidekiq -> RailsCommands.insert!(context.repo, "points.anomaly_recalculate", payload)
          end
        end)
    end)
  end

  defp insert_track!(repo, payload, track) do
    repo.query!(
      """
      INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,scheduled_at)
      VALUES($1,'points.anomaly_recalculate',1,$2,$3,$4,NOW())
      """,
      [Ecto.UUID.bingenerate(), payload, %{"producer" => "Phoenix Points::AnomalyFilter"}, track],
      log: false
    )

    :ok
  end

  defp months(context, flagged) do
    context.repo.query!(
      "SELECT DISTINCT extract(year FROM to_timestamp(at) AT TIME ZONE $2)::int,extract(month FROM to_timestamp(at) AT TIME ZONE $2)::int FROM unnest($1::bigint[]) AS t(at) ORDER BY 1,2",
      [Enum.map(flagged, fn [_id, _track, at] -> at end), context.zone],
      log: false
    ).rows
  end
end
