defmodule Dawarich.MapMatching.TestSupport do
  alias Dawarich.Tracks.{Points, Settings}
  alias Dawarich.Tracks.MapMatching.{State, Worker}

  def await_hooks!, do: Dawarich.MapMatchingTasks.await!()

  def setup! do
    settings = ~w(MAP_MATCHING_ENABLED ATLAS_URL MAP_MATCHING_SHADOW_MODE)
    saved = Map.new(settings, &{&1, System.get_env(&1)})
    old = Application.get_env(:dawarich, :map_matching_oban)
    client = Application.get_env(:dawarich, :map_matching_client)
    System.put_env("MAP_MATCHING_ENABLED", "true")
    System.put_env("ATLAS_URL", "http://atlas.test")
    System.delete_env("MAP_MATCHING_SHADOW_MODE")
    Application.put_env(:dawarich, :map_matching_oban, Dawarich.TracksCase.oban())
    Dawarich.Experimental.refresh_map_matching(Dawarich.TracksScratchRepo)

    ExUnit.Callbacks.on_exit(fn ->
      await_hooks!()

      for {key, value} <- saved do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      Dawarich.Experimental.cache_map_matching(Dawarich.TracksScratchRepo, false)

      restore(:map_matching_oban, old)
      restore(:map_matching_client, client)
    end)

    :ok
  end

  def accounting(repo, fun) do
    caller = self()
    tracer = spawn(fn -> account_loop(caller, %{sql: [], spawned: 0, supervised: 0}) end)
    dispatcher = Process.whereis(Dawarich.Tracks.MapMatching.Deferred)
    supervisor = Process.whereis(Dawarich.Tracks.MapMatching.Tasks)
    handler = {__MODULE__, make_ref()}
    event = repo.config()[:telemetry_prefix] ++ [:query]
    :ok = :telemetry.attach(handler, event, &__MODULE__.account_query/4, tracer)
    :erlang.trace(caller, true, [:procs, :set_on_spawn, {:tracer, tracer}])
    :erlang.trace(dispatcher, true, [:procs, :set_on_spawn, {:tracer, tracer}])
    :erlang.trace(supervisor, true, [:procs, :set_on_spawn, {:tracer, tracer}])

    try do
      fun.()
      await_hooks!()
      ref = :erlang.trace_delivered(:all)
      receive do: ({:trace_delivered, :all, ^ref} -> :ok)
      send(tracer, :snapshot)
      receive do: ({:counts, counts} -> %{counts | sql: Enum.sort(counts.sql)})
    after
      :erlang.trace(caller, false, [:procs, :set_on_spawn])
      :erlang.trace(dispatcher, false, [:procs, :set_on_spawn])
      :erlang.trace(supervisor, false, [:procs, :set_on_spawn])
      :telemetry.detach(handler)
      send(tracer, :stop)
    end
  end

  def account_query(_, _, meta, tracer), do: send(tracer, {:sql, meta.query})

  defp account_loop(caller, counts) do
    receive do
      {:sql, query} ->
        account_loop(caller, %{counts | sql: [query | counts.sql]})

      {:trace, parent, :spawn, _, _} ->
        supervised =
          if parent == Process.whereis(Dawarich.Tracks.MapMatching.Tasks), do: 1, else: 0

        account_loop(caller, %{
          counts
          | spawned: counts.spawned + 1,
            supervised: counts.supervised + supervised
        })

      :snapshot ->
        send(caller, {:counts, counts})
        account_loop(caller, counts)

      :stop ->
        :ok

      _ ->
        account_loop(caller, counts)
    end
  end

  defp restore(key, nil), do: Application.delete_env(:dawarich, key)
  defp restore(key, value), do: Application.put_env(:dawarich, key, value)

  def input!(repo, opts \\ []) do
    user =
      Dawarich.TracksCase.user!(%{
        "enabled_transportation_modes" => ~w(walking cycling driving bus)
      })

    start = Keyword.get(opts, :start, 1_791_288_000)
    id = Dawarich.TracksCase.track!(user.id, nil, start, start + 60)

    for {offset, lon} <- [{0, 13.0}, {60, 13.001}] do
      Dawarich.TracksCase.point!(user.id, start + offset, lon, 52.0, track_id: id)
    end

    if Keyword.get(opts, :eligible, true), do: segment!(repo, id)

    if Keyword.get(opts, :demo, false),
      do: repo.query!("UPDATE tracks SET demo=true WHERE id=$1", [id])

    %{
      id: id,
      user: Settings.load!(repo, user.id),
      points:
        Points.load_chunk(repo, user.id, start, start + 60, untracked_only: false, import_id: nil)
    }
  end

  def segment!(repo, id) do
    repo.query!(
      "INSERT INTO track_segments(track_id,start_index,end_index,transportation_mode,distance,duration,avg_speed,max_speed,confidence,created_at,updated_at) VALUES($1,0,1,2,100,60,6,6,1,now(),now())",
      [id],
      log: false
    )
  end

  def jobs(repo, id) do
    repo.query!(
      "SELECT args FROM oban.oban_jobs WHERE worker=$1 AND args->>'track_id'=$2 ORDER BY id",
      [inspect(Worker), to_string(id)],
      log: false
    ).rows
    |> List.flatten()
  end

  def stale!(repo, id) do
    state = State.read(repo, id)

    State.write!(repo, id, %{
      data:
        Map.put(
          state.data,
          "claimed_at",
          DateTime.utc_now() |> DateTime.add(-3601) |> DateTime.to_iso8601()
        )
    })
  end

  def fail_insert!(repo) do
    repo.query!(
      "ALTER TABLE oban.oban_jobs ADD CONSTRAINT mm_insert_probe CHECK (queue <> 'map_matching') NOT VALID",
      [],
      log: false
    )

    ExUnit.Callbacks.on_exit(fn ->
      repo.query!("ALTER TABLE oban.oban_jobs DROP CONSTRAINT IF EXISTS mm_insert_probe", [],
        log: false
      )
    end)
  end

  def success(_url, _payload) do
    {:ok,
     %{
       geometry: %{type: "LineString", coordinates: [[13.0, 52.0], [13.001, 52.0]]},
       stats: %{
         matched: 2,
         unmatched: 0,
         confidence_score: 1.0,
         mean_distance_from_trace_point: 0.0,
         p95_distance_from_trace_point: 0.0,
         max_distance_from_trace_point: 0.0
       },
       provider: %{}
     }}
  end
end
