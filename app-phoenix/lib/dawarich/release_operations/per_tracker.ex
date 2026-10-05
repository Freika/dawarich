defmodule Dawarich.ReleaseOperations.PerTracker do
  @moduledoc false
  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 26

  alias Dawarich.ReleaseOperations, as: Ops
  alias Dawarich.Points.{DeviceTagBackfill, TrackerBackfill}
  alias Dawarich.Users.{RecalculationArgs, RecalculationPeriod, RecalculateWorker}

  @pending """
  SELECT u.id FROM users u WHERE u.deleted_at IS NULL AND u.id>$1 AND (
    EXISTS(SELECT 1 FROM tracks t WHERE t.user_id=u.id AND t.tracker_id IS NULL)
    OR EXISTS(SELECT 1 FROM points p WHERE p.user_id=u.id AND p.tracker_id IN ('google-maps-timeline-export','google-maps-phone-timeline-export'))
    OR EXISTS(SELECT 1 FROM points p JOIN imports i ON i.id=p.import_id
      WHERE p.user_id=u.id AND i.source=2 AND p.tracker_id LIKE 'legacy-import-%'))
  ORDER BY u.id LIMIT 1000
  """

  def command_type, do: "release.per_tracker"

  def args_from_command(version, payload) do
    with {:ok, request} <- RecalculationArgs.decode(command_type(), version, payload),
         do: {:ok, %{"version" => 1, "cursor" => %{"request" => request, "after_id" => 0}}}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{conf: conf} = job),
    do: Ops.run(Dawarich.Jobs.repo(), conf.name, __MODULE__, job)

  def step(repo, %{cursor: %{"request" => %{"user_id" => nil}}} = op) do
    Ops.commit(repo, op, fn ->
      ids = Ops.ids(repo, @pending, [op.cursor["after_id"]])
      rand = Keyword.get(op.opts, :rand, fn 0..3600 -> :rand.uniform(3601) - 1 end)
      now = Keyword.get_lazy(op.opts, :now, &DateTime.utc_now/0)

      for id <- ids do
        source = Ecto.UUID.generate()
        request = Map.merge(op.cursor["request"], %{"user_id" => id, "source_job_id" => source})
        {:ok, args} = args_from_command(1, request)
        delay = rand.(0..3600)

        Oban.insert!(
          op.oban,
          new(Map.put(args, "event_id", source), scheduled_at: DateTime.add(now, delay))
        )
      end

      if length(ids) < 1000, do: :done, else: {Map.put(op.cursor, "after_id", List.last(ids)), 0}
    end)
  end

  def step(repo, %{cursor: %{"request" => request}} = op) do
    if Ops.user?(repo, request["user_id"]) do
      devices =
        Ops.ids(repo, "SELECT id FROM imports WHERE user_id=$1 AND source=2 ORDER BY id", [
          request["user_id"]
        ])
        |> Enum.reduce(0, fn id, n ->
          n +
            DeviceTagBackfill.run(repo, id, Keyword.put(op.opts, :zone, request["ambient_zone"]))
        end)

      raw = TrackerBackfill.run(repo, request["user_id"])
      if hook = op.opts[:after_repair], do: hook.(devices, raw)

      result =
        if devices + raw > 0 or needs_recalculation?(repo, request["user_id"]),
          do: recalculate(repo, op),
          else: :ok

      with :ok <- result, do: Ops.commit(repo, op, fn -> :done end)
    else
      Ops.commit(repo, op, fn -> :done end)
    end
  end

  def needs_recalculation?(repo, id) do
    Ops.value(
      repo,
      """
      SELECT EXISTS(SELECT 1 FROM tracks WHERE user_id=$1 AND tracker_id IS NULL)
      OR EXISTS(SELECT 1 FROM points WHERE user_id=$1 AND track_id IS NULL)
      OR EXISTS(SELECT 1 FROM points p JOIN tracks t ON t.id=p.track_id
        WHERE p.user_id=$1 AND p.tracker_id IS DISTINCT FROM t.tracker_id)
      """,
      [id]
    )
  end

  defp recalculate(repo, op) do
    request = op.cursor["request"]
    id = RecalculationPeriod.command_id("release.per_tracker.rebuild:#{request["source_job_id"]}")

    args = %{
      "user_id" => request["user_id"],
      "year" => nil,
      "notify" => false,
      "job_queue" => nil,
      "source_job_id" => id,
      "event_id" => id,
      "ambient_zone" => request["ambient_zone"]
    }

    RecalculateWorker.inline(repo, op.oban, args, fn -> :ok end, op.opts)
  end
end
