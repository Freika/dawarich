defmodule Dawarich.Tracks.BackfillCommands do
  @moduledoc false

  alias Dawarich.Tracks.{BackfillRanges, BackfillWalks}
  alias Dawarich.{RailsCommands, TimeZoneName}

  def ingest(repo, user_id, timestamps, opts) do
    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id = $1", [user_id], log: false).rows

    opts =
      opts
      |> Keyword.put_new(:time_zone, Dawarich.UserSettings.safe(settings)["timezone"])
      |> Keyword.put(:legacy_ingest, true)

    put(repo, user_id, timestamps, opts)
  end

  def put(repo, user_id, timestamps, opts \\ []) do
    zone = user_zone(repo, opts[:time_zone])
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    transaction(repo, "tracks.backfill", fn
      :oban ->
        unwrap(
          repo,
          BackfillRanges.put(repo, user_id, timestamps, zone, now, fn range ->
            publish(
              repo,
              "tracks.backfill",
              range.cycle_id,
              user_id,
              %{
                "user_id" => user_id,
                "cycle_id" => range.cycle_id,
                "time_zone" => range.time_zone
              },
              range.due_at
            )
          end)
        )

      :sidekiq ->
        payload = %{"user_id" => user_id, "timestamps" => timestamps}
        payload = if opts[:legacy_ingest], do: payload, else: Map.put(payload, "time_zone", zone)
        RailsCommands.insert!(repo, "tracks.backfill", payload)

        :ok
    end)
  end

  def schedule(repo, user_id, opts \\ []) do
    zone = user_zone(repo, opts[:time_zone])
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    transaction(repo, "tracks.throttled_backfill", fn
      :oban ->
        if not Dawarich.Standalone.enabled?() and legacy_pending?(user_id) do
          reverse_bootstrap(repo, user_id, zone)
        else
          unwrap(
            repo,
            BackfillWalks.schedule(repo, user_id, zone, now, fn walk ->
              publish(
                repo,
                "tracks.throttled_backfill",
                walk.walk_id,
                user_id,
                %{
                  "user_id" => user_id,
                  "walk_id" => walk.walk_id,
                  "cursor_timestamp" => nil,
                  "time_zone" => zone
                },
                walk.due_at
              )
            end)
          )
        end

      :sidekiq ->
        reverse_bootstrap(repo, user_id, zone)
    end)
  end

  defp legacy_pending?(user_id) do
    case Dawarich.Redis.command(["PTTL", "track_throttled_backfill:user:#{user_id}"]) do
      {:ok, ttl} when ttl == -2 -> false
      _ -> true
    end
  end

  defp reverse_bootstrap(repo, user_id, zone) do
    RailsCommands.insert!(repo, "tracks_throttled_backfill", %{
      "user_id" => user_id,
      "time_zone" => zone
    })
  end

  def user_zone(repo, name) do
    fallback = System.get_env("TIME_ZONE", "Europe/Berlin") |> TimeZoneName.to_iana()
    name = if is_binary(name) and name != "", do: TimeZoneName.to_iana(name), else: fallback

    [[zone]] =
      repo.query!(
        "SELECT name FROM pg_timezone_names WHERE name = ANY($1) ORDER BY array_position($1, name) LIMIT 1",
        [[name, fallback, "UTC"]],
        log: false
      ).rows

    zone
  end

  defp transaction(repo, kind, fun) do
    unwrap(
      repo,
      repo.transaction(fn -> fun.(Dawarich.Tracks.Owner.lock(repo, "command:" <> kind)) end)
    )
  end

  defp unwrap(_repo, {:ok, result}), do: result
  defp unwrap(repo, {:error, reason}), do: repo.rollback(reason)

  defp publish(repo, kind, event, user_id, payload, at) do
    repo.query!(
      """
      INSERT INTO public.job_outbox (event_id, command_type, command_version, payload, aggregate_id, metadata, scheduled_at)
      VALUES ($1, $2, 1, $3, $4, $5, $6) ON CONFLICT (event_id) DO NOTHING
      """,
      [
        Ecto.UUID.dump!(event),
        kind,
        payload,
        user_id,
        %{"producer" => "phoenix.tracks.backfill"},
        at
      ],
      log: false
    )

    :ok
  end
end
