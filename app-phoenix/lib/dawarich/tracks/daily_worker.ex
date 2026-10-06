defmodule Dawarich.Tracks.DailyWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: :infinity, states: :incomplete]

  require Logger

  alias Dawarich.Jobs.Ownership
  alias Dawarich.RailsCommands
  alias Dawarich.Tracks.RangeWorker
  alias DawarichWeb.LayoutAssigns

  @key "cron:daily_track_generation_job"
  @range_key "command:tracks.generate_range"
  @batch_size 1_000
  @bootstrap_limit 100_000
  @url_namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F,
                   0xD4, 0x30, 0xC8>>

  @batch """
  SELECT u.id,
    COALESCE((SELECT floor(extract(epoch FROM max(t.end_at)))::bigint + 1 FROM tracks t WHERE t.user_id = u.id),
             (SELECT min(p.timestamp) FROM points p WHERE p.user_id = u.id),
             floor(extract(epoch FROM to_timestamp($2) - interval '1 week'))::bigint) AS start_ts,
    EXISTS (SELECT 1 FROM tracks t WHERE t.user_id = u.id) AS has_tracks,
    COALESCE(u.settings->>'timezone', '') AS timezone
  FROM users u
  WHERE u.deleted_at IS NULL AND u.status IN (1, 2) AND u.points_count IS DISTINCT FROM 0 AND u.id > $1
  ORDER BY u.id LIMIT #{@batch_size}
  """

  @due "SELECT EXISTS (SELECT 1 FROM points WHERE user_id = $1 AND timestamp >= $2)"
  @history "SELECT count(*) FROM (SELECT 1 FROM points WHERE user_id = $1 LIMIT #{@bootstrap_limit + 1}) s"
  @zone "SELECT name FROM pg_timezone_names WHERE name = ANY($1) ORDER BY array_position($1, name) LIMIT 1"

  def key, do: @key

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job), do: run(Dawarich.Jobs.repo(), conf.name, slot(job))

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(55)

  def slot(%Oban.Job{inserted_at: inserted_at}),
    do: inserted_at |> DateTime.to_unix() |> div(60) |> Kernel.*(60)

  def event_id(slot, user_id) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha, @url_namespace <> "tracks.daily:#{slot}:#{user_id}")

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end

  def run(repo, oban, slot, opts \\ []), do: sweep(repo, oban, slot, opts, 0)

  defp sweep(repo, oban, slot, opts, after_id) do
    case Ownership.with_owner(repo, @key, :oban, fn ->
           batch(repo, oban, slot, opts, after_id)
         end) do
      {:ok, {:next, last_id}} -> sweep(repo, oban, slot, opts, last_id)
      {:ok, :done} -> :ok
      {:skip, _owner} -> {:cancel, :not_owner}
      {:error, reason} -> {:error, reason}
    end
  end

  defp batch(repo, oban, slot, opts, after_id) do
    users = repo.query!(@batch, [after_id, slot], log: false).rows
    Enum.each(users, &process_safely(repo, oban, slot, opts, &1))

    if length(users) == @batch_size, do: {:next, users |> List.last() |> hd()}, else: :done
  end

  defp process_safely(repo, oban, slot, opts, [user_id | _] = row) do
    repo.query!("SAVEPOINT daily_user", [], log: false)

    try do
      process(repo, oban, slot, opts, row)
      Keyword.get(opts, :hook, fn _user_id -> :ok end).(user_id)
      repo.query!("RELEASE SAVEPOINT daily_user", [], log: false)
    rescue
      error ->
        repo.query!("ROLLBACK TO SAVEPOINT daily_user", [], log: false)
        repo.query!("RELEASE SAVEPOINT daily_user", [], log: false)

        Logger.error(
          "Failed to process daily tracks for user #{user_id}: #{Exception.message(error)}"
        )
    end
  end

  defp process(repo, oban, slot, opts, [user_id, start_ts, has_tracks, timezone]) do
    cond do
      not one!(repo, @due, [user_id, start_ts]) ->
        :skipped

      blocked?(repo, user_id, has_tracks) ->
        Dawarich.Tracks.BackfillCommands.schedule(
          repo,
          user_id,
          Keyword.put(opts, :time_zone, timezone)
        )

      true ->
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        payload = payload(repo, user_id, start_ts, now, timezone)
        start(repo, oban, payload, event_id(slot, user_id))
    end
  end

  defp blocked?(repo, user_id, has_tracks),
    do:
      not LayoutAssigns.self_hosted?() and not has_tracks and
        one!(repo, @history, [user_id]) > @bootstrap_limit

  defp start(repo, oban, payload, event_id) do
    case Dawarich.Tracks.Owner.lock(repo, @range_key) do
      :oban ->
        Oban.insert!(
          oban,
          RangeWorker.new(Map.put(payload, "event_id", event_id),
            unique: [keys: [:event_id], period: :infinity, states: :all]
          )
        )

      :sidekiq ->
        RailsCommands.insert!(repo, "tracks_generate_range", payload)
    end
  end

  defp payload(repo, user_id, start_ts, now, timezone) do
    %{
      "user_id" => user_id,
      "start_at" => start_ts |> DateTime.from_unix!() |> iso(),
      "end_at" => iso(now),
      "time_zone" => one!(repo, @zone, [[timezone, System.get_env("TIME_ZONE"), "UTC"]]),
      "mode" => "daily",
      "untracked_only" => false,
      "import_id" => nil,
      "low_priority" => false
    }
  end

  defp iso(%DateTime{microsecond: {us, _precision}} = at),
    do: DateTime.to_iso8601(%{at | microsecond: {us, 6}})

  defp one!(repo, sql, params) do
    [[value]] = repo.query!(sql, params, log: false).rows
    value
  end
end
