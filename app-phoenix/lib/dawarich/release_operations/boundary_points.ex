defmodule Dawarich.ReleaseOperations.BoundaryPoints do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26
  alias Dawarich.ReleaseOperations

  @sql """
  WITH target AS (SELECT id,name,geom FROM countries WHERE iso_a2='UA' ORDER BY id LIMIT 1),
  batch AS (
    SELECT p.id FROM points p,target t
    WHERE p.country_id IN (SELECT id FROM countries WHERE iso_a2='RU')
      AND ST_Intersects(p.lonlat,ST_MakeEnvelope(32.4,44.3,36.7,46.3,4326)::geography)
      AND ST_Covers(t.geom,p.lonlat::geometry)
    ORDER BY p.id LIMIT 10000
  ), moved AS (
    UPDATE points p SET country_id=t.id,
      country_name=CASE WHEN COALESCE(p.country_name,'')='' OR p.country_name IN (SELECT name FROM countries WHERE iso_a2='RU') THEN t.name ELSE p.country_name END,
      country=CASE WHEN COALESCE(p.country,'')='' OR p.country IN (SELECT name FROM countries WHERE iso_a2='RU') THEN t.name ELSE p.country END,
      updated_at=now()
    FROM batch,target t WHERE p.id=batch.id
    RETURNING p.user_id,p."timestamp"/86400 AS day
  ) SELECT DISTINCT user_id,day FROM moved
  """
  def command_type, do: "release.boundary_points"

  def args_from_command(1, payload) when map_size(payload) == 0,
    do: {:ok, %{"version" => 1, "cursor" => %{"batch" => 0}}}

  def args_from_command(1, _), do: {:error, "invalid_payload"}
  def args_from_command(_, _), do: {:error, "unsupported_version"}
  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(Dawarich.Jobs.repo(), Oban, job)

  def run(repo, oban, job),
    do: ReleaseOperations.run(repo, oban, __MODULE__, job, fail_on_error: true)

  def step(repo, op) do
    ReleaseOperations.commit(repo, op, fn ->
      moved = repo.query!(@sql, [], log: false, timeout: :infinity).rows

      for [user, day] <- moved do
        timestamp = day * 86400
        Dawarich.Stats.GeocodedDays.mark(repo, user, timestamp)

        Oban.insert!(
          op.oban,
          Dawarich.Achievements.CheckWorker.new(%{
            "user_id" => user,
            "notify" => true,
            "oldest_timestamp" => timestamp
          })
        )
      end

      if moved == [], do: :done, else: {%{"batch" => op.cursor["batch"] + 1}, 0}
    end)
  end
end
