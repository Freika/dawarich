defmodule Dawarich.RouteVideos.Retention do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.RouteVideos.Writes
  alias Dawarich.RubyInteger

  def policy(env) do
    %{
      retention_days: limit(env["VIDEO_RETENTION_DAYS"], 30),
      max_per_user: limit(env["VIDEO_MAX_PER_USER"], 10)
    }
  end

  defp limit(value, default),
    do: max(if(Ruby.blank?(value), do: default, else: RubyInteger.to_i(value)), 0)

  def expire_over_cap(_repo, _user_id, 0, _now), do: []

  def expire_over_cap(repo, user_id, cap, now) do
    repo.query!(
      "SELECT id FROM route_videos WHERE user_id=$1 AND status=0 ORDER BY created_at DESC,id DESC OFFSET $2",
      [user_id, cap],
      log: false
    ).rows
    |> List.flatten()
    |> Enum.flat_map(&expire(repo, &1, now))
  end

  def expire_aged(_repo, 0, _now), do: []

  def expire_aged(repo, days, now) do
    [[cutoff]] =
      Dawarich.UserTimeZone.query!(
        "SELECT ((($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE z.name - $2::int * interval '1 day') AT TIME ZONE z.name) AT TIME ZONE 'UTC' FROM z",
        [DateTime.to_naive(now), days],
        %{"timezone" => System.get_env("TIME_ZONE", "Europe/Berlin")},
        repo
      ).rows

    aged_batch(repo, cutoff, now, 0)
  end

  defp aged_batch(repo, cutoff, now, last) do
    ids =
      repo.query!(
        "SELECT id FROM route_videos WHERE status=0 AND created_at < $1 AND id > $2 ORDER BY id LIMIT 500",
        [cutoff, last],
        log: false
      ).rows
      |> List.flatten()

    case ids do
      [] ->
        []

      _ ->
        Enum.flat_map(ids, &expire(repo, &1, now)) ++
          aged_batch(repo, cutoff, now, List.last(ids))
    end
  end

  def expire(repo, id, now) do
    stamp = DateTime.to_naive(now)

    {:ok, eligible} =
      repo.transaction(fn ->
        case repo.query!(
               "SELECT user_id,name FROM route_videos WHERE id=$1 AND status=0 FOR UPDATE",
               [id],
               log: false
             ).rows do
          [[user_id, name]] ->
            Writes.detach(repo, user_id, id, stamp)
            {:expire, name}

          [] ->
            false
        end
      end)

    if eligible do
      {:expire, name} = eligible
      if Ruby.blank?(name), do: raise("route video name validation")

      repo.query!(
        "UPDATE route_videos SET status=1,expired_at=$2,updated_at=$2 WHERE id=$1 AND status=0 RETURNING id",
        [id, stamp],
        log: false
      ).rows
      |> List.flatten()
    else
      []
    end
  end

  def run(repo, now, policy) do
    expire_aged(repo, policy.retention_days, now)

    if policy.max_per_user > 0 do
      repo.query!(
        "SELECT user_id FROM route_videos WHERE status=0 GROUP BY user_id HAVING count(*) > $1",
        [policy.max_per_user],
        log: false
      ).rows
      |> List.flatten()
      |> Enum.each(&expire_over_cap(repo, &1, policy.max_per_user, now))
    end

    :ok
  end
end
