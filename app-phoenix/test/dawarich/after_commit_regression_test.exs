defmodule AfterCommitRegressionRepo do
  def query!(sql, params \\ [], opts \\ []) do
    if Process.get(:probe_stats_failure) && String.starts_with?(sql, "UPDATE stats"),
      do: raise("simulated calculation failure")

    if Process.get(:probe_barrier) && String.contains?(sql, "FROM users") &&
         String.contains?(sql, "FOR UPDATE"),
       do: send(Process.get(:probe_barrier), {:locking, self()})

    result = Dawarich.ScratchRepo.query!(sql, params, opts)

    barrier_query =
      String.contains?(sql, "AND accuracy > 10000") or
        String.starts_with?(
          sql,
          "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker'"
        )

    if Process.get(:probe_barrier) && barrier_query do
      send(Process.get(:probe_barrier), {:selected, self()})

      receive do
        :continue -> :ok
      after
        5_000 -> raise "probe barrier timeout"
      end
    end

    result
  end

  def transaction(fun), do: Dawarich.ScratchRepo.transaction(fun)
  def in_transaction?(), do: Dawarich.ScratchRepo.in_transaction?()
  def rollback(reason), do: Dawarich.ScratchRepo.rollback(reason)

  def insert!(changeset, opts) do
    if Process.get(:probe_insert_failure), do: raise("simulated enqueue failure")
    Dawarich.ScratchRepo.insert!(changeset, opts)
  end
end

defmodule AfterCommitRegressionStore do
  def append(repo, namespace, channel, payload) do
    if Process.get(:probe_publish_failure),
      do: {:error, :simulated_publish_failure},
      else: Dawarich.Cable.PgStore.append(repo, namespace, channel, payload)
  end
end

defmodule AfterCommitRegressionStatsRepo do
  def query!(sql, params \\ [], opts \\ []), do: Dawarich.ScratchRepo.query!(sql, params, opts)
  def insert!(changeset, opts), do: Dawarich.ScratchRepo.insert!(changeset, opts)
  def in_transaction?(), do: Dawarich.ScratchRepo.in_transaction?()
  def get_dynamic_repo(), do: Dawarich.ScratchRepo.get_dynamic_repo()

  def transaction(fun) do
    Dawarich.ScratchRepo.transaction(fn ->
      result = fun.()
      {user, key} = Process.get(:probe_repopulate)

      _old =
        Task.async(fn ->
          [[distance]] =
            Dawarich.ScratchRepo.query!("SELECT distance FROM stats WHERE user_id=$1", [user],
              log: false
            ).rows

          {:ok, _} = Dawarich.Redis.cache_command(["SET", key, to_string(distance)])
          distance
        end)
        |> Task.await()

      result
    end)
  end
end

defmodule AfterCommitRegressionCacheConnection do
  use GenServer
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: Dawarich.Redis.Cache)
  def init(opts), do: {:ok, opts}

  def handle_cast({:pipeline, [command], from}, state) do
    response =
      case command do
        ["SCAN", _, "MATCH", pattern | _] ->
          keys = if String.starts_with?(pattern, "insights/"), do: [state.key], else: []
          {:ok, [["0", keys]]}

        ["UNLINK", key] when key == state.key ->
          send(state.parent, :digest_unlink_failed)
          {:error, %Redix.ConnectionError{reason: :closed}}

        ["UNLINK" | _] ->
          {:ok, [4]}
      end

    send(from, {from, response})
    {:noreply, state}
  end
end

defmodule AfterCommitRegressionProbes do
  use Dawarich.JobsCase, async: false
  import Dawarich.AnomalyCase
  alias Dawarich.Points.{AnomalyArrivalWorker, AnomalyStatsWorker, LiveBroadcastWorker}
  @at DateTime.to_unix(~U[2026-01-01 00:00:00Z])

  setup do
    rails = System.get_env("DAWARICH_RAILS")
    cable = Application.get_env(:dawarich, :cable)
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if rails,
        do: System.put_env("DAWARICH_RAILS", rails),
        else: System.delete_env("DAWARICH_RAILS")

      Application.put_env(:dawarich, :cable, cable)
    end)

    :ok
  end

  test "F2 anomaly stats propagates calculation failure for retry" do
    user = stats_user()
    Process.put(:probe_stats_failure, true)
    result = AnomalyStatsWorker.run(AfterCommitRegressionRepo, stats_args(user))
    Process.delete(:probe_stats_failure)
    assert rows("SELECT distance FROM stats WHERE user_id=$1", [user]) == [[999]]
    assert rows("SELECT count(*) FROM notifications WHERE user_id=$1", [user]) == [[1]]
    assert match?({:error, _}, result)
  end

  test "F1 anomaly stats retains cache and cancels intent on rollback" do
    start_cache()
    user = stats_user()
    key = "dawarich/user_#{user}_total_distance"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "999"])

    {:error, :probe_rollback} =
      ScratchRepo.transaction(fn ->
        assert :ok = AnomalyStatsWorker.run(ScratchRepo, stats_args(user))
        ScratchRepo.rollback(:probe_rollback)
      end)

    value = Dawarich.Redis.cache_command(["GET", key])
    assert rows("SELECT distance FROM stats WHERE user_id=$1", [user]) == [[999]]
    assert value == {:ok, "999"}
  end

  test "F5 anomaly arrival rolls back flags when durable publication fails" do
    user = user!()
    point = point!(user, @at, {13.4, 52.5}, accuracy: 20_000)
    Process.put(:probe_insert_failure, true)

    assert_raise RuntimeError, "simulated enqueue failure", fn ->
      AnomalyArrivalWorker.run(AfterCommitRegressionRepo, arrival_args(user))
    end

    Process.delete(:probe_insert_failure)
    assert :ok = AnomalyArrivalWorker.run(ScratchRepo, arrival_args(user))
    jobs = rows("SELECT worker FROM oban.oban_jobs ORDER BY id")
    assert flagged(user) == [point]
    assert length(jobs) == 2
  end

  test "F5 concurrent anomaly arrivals publish each follow-up once" do
    user = user!()
    point!(user, @at, {13.4, 52.5}, accuracy: 20_000)
    parent = self()

    first_task =
      Task.async(fn ->
        Process.put(:probe_barrier, parent)
        AnomalyArrivalWorker.run(AfterCommitRegressionRepo, arrival_args(user))
      end)

    assert_receive {:selected, first}, 5_000

    second_task =
      Task.async(fn ->
        Process.put(:probe_barrier, parent)
        send(parent, {:started, self()})
        AnomalyArrivalWorker.run(AfterCommitRegressionRepo, arrival_args(user))
      end)

    assert_receive {:started, second_pid}, 5_000
    assert_receive {:locking, ^second_pid}, 5_000
    send(first, :continue)
    assert_receive {:selected, second}, 5_000
    send(second, :continue)
    for task <- [first_task, second_task], do: assert(Task.await(task) == :ok)
    jobs = rows("SELECT worker,count(*) FROM oban.oban_jobs GROUP BY worker ORDER BY worker")

    assert jobs == [
             ["Dawarich.Points.AnomalyStatsWorker", 1],
             ["Dawarich.Points.TileEpochWorker", 1]
           ]
  end

  test "F8 failed native live publication rolls back claim and whole batch" do
    user = user!()

    Application.put_env(:dawarich, :cable,
      transport: :pg,
      repo: ScratchRepo,
      pg_store: AfterCommitRegressionStore
    )

    args = %{
      "user_id" => user,
      "broadcast_id" => Ecto.UUID.generate(),
      "payloads" => [],
      "upserted" => [%{"id" => 1, "timestamp" => @at, "longitude" => 13.4, "latitude" => 52.5}]
    }

    Process.put(:probe_publish_failure, true)
    assert_raise MatchError, fn -> LiveBroadcastWorker.run(ScratchRepo, args) end
    Process.delete(:probe_publish_failure)
    assert :ok = LiveBroadcastWorker.run(ScratchRepo, args)
    count = rows("SELECT count(*) FROM phoenix.cable_events")
    assert Dawarich.State.claimed?(ScratchRepo, "live_broadcast:done:#{args["broadcast_id"]}")
    assert count == [[1]]
  end

  test "F4 coexistence area relabel keeps cached months until commit" do
    start_cache()
    System.delete_env("DAWARICH_RAILS")
    user = user!(%{"timezone" => "UTC"})
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)

    [[area]] =
      rows(
        "INSERT INTO areas(user_id,name,latitude,longitude,radius,created_at,updated_at) VALUES($1,'Synthetic area',52.5,13.4,200,now(),now()) RETURNING id",
        [user]
      )

    [[place]] =
      rows(
        "INSERT INTO places(user_id,name,latitude,longitude,created_at,updated_at) VALUES($1,'Synthetic place',52.5,13.4,now(),now()) RETURNING id",
        [user]
      )

    rows(
      "INSERT INTO visits(user_id,place_id,name,status,detection_version,duration,started_at,ended_at,created_at,updated_at) VALUES($1,$2,'Original',0,1,60,'2026-01-01 00:00:00','2026-01-01 01:00:00',now(),now())",
      [user, place]
    )

    key = "timeline_month_summary/#{user}/2026-01/UTC/pro/v3"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "original-cache"])

    {:error, :probe_rollback} =
      ScratchRepo.transaction(fn ->
        assert :ok = Dawarich.Areas.relabel(ScratchRepo, area)
        ScratchRepo.rollback(:probe_rollback)
      end)

    value = Dawarich.Redis.cache_command(["GET", key])
    assert rows("SELECT name FROM visits WHERE user_id=$1", [user]) == [["Original"]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert value == {:ok, "original-cache"}
  end

  test "F1 reader repopulation is repaired by committed invalidation intent" do
    start_cache()
    user = stats_user()
    point!(user, @at, {13.4, 52.5})
    key = "dawarich/user_#{user}_total_distance"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "999"])
    Process.put(:probe_repopulate, {user, key})
    assert :ok = AnomalyStatsWorker.run(AfterCommitRegressionStatsRepo, stats_args(user))
    assert Dawarich.Redis.cache_command(["GET", key]) == {:ok, "999"}
    [[args]] = rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.AfterCommit.Worker'")
    assert :ok = Dawarich.AfterCommit.Worker.run(ScratchRepo, args)
    value = Dawarich.Redis.cache_command(["GET", key])
    assert rows("SELECT distance FROM stats WHERE user_id=$1", [user]) == [[0]]
    assert value == {:ok, nil}
  end

  test "F7 concurrent API deletes coalesce one achievement job and oldest timestamp" do
    user = user!(%{"timezone" => "UTC"})
    foreign = user!()
    first = point!(user, @at, {13.4, 52.5})
    second = point!(user, @at + 1, {13.4, 52.5})
    other = point!(foreign, @at, {13.4, 52.5})
    rows("UPDATE users SET points_count=2 WHERE id=$1", [user])
    actor = %{id: user, settings: %{"timezone" => "UTC"}, status: 1, active_until: nil, plan: 2}
    ctx = %{now: DateTime.utc_now(), self_hosted?: true}
    parent = self()

    one_task =
      Task.async(fn ->
        Process.put(:probe_barrier, parent)

        Dawarich.Points.ApiWrites.bulk_destroy(
          AfterCommitRegressionRepo,
          actor,
          %{"point_ids" => [first, other]},
          ctx
        )
      end)

    assert_receive {:selected, one}, 5_000

    two_task =
      Task.async(fn ->
        Process.put(:probe_barrier, parent)
        send(parent, {:started, self()})

        Dawarich.Points.ApiWrites.bulk_destroy(
          AfterCommitRegressionRepo,
          actor,
          %{"point_ids" => [second, other]},
          ctx
        )
      end)

    assert_receive {:started, second_pid}, 5_000
    assert_receive {:locking, ^second_pid}, 5_000
    send(one, :continue)
    assert_receive {:selected, two}, 5_000
    send(two, :continue)

    for task <- [one_task, two_task],
        do: assert(match?({:ok, 200, %{"count" => 1}}, Task.await(task)))

    jobs =
      rows(
        "SELECT args->>'oldest_timestamp' FROM oban.oban_jobs WHERE worker='Dawarich.Achievements.CheckWorker' ORDER BY id"
      )

    assert jobs == [[to_string(@at)]]
  end

  test "F6 failed API follow-up rolls back deletion and counters" do
    user = user!(%{"timezone" => "UTC"})
    point = point!(user, @at, {13.4, 52.5})
    rows("UPDATE users SET points_count=1 WHERE id=$1", [user])
    actor = %{id: user, settings: %{"timezone" => "UTC"}, status: 1, active_until: nil, plan: 2}
    ctx = %{now: DateTime.utc_now(), self_hosted?: true}
    params = %{"point_ids" => [point]}
    Process.put(:probe_insert_failure, true)

    assert_raise RuntimeError, "simulated enqueue failure", fn ->
      Dawarich.Points.ApiWrites.bulk_destroy(AfterCommitRegressionRepo, actor, params, ctx)
    end

    Process.delete(:probe_insert_failure)
    assert rows("SELECT id FROM points WHERE id=$1", [point]) == [[point]]
    assert rows("SELECT points_count FROM users WHERE id=$1", [user]) == [[1]]

    assert {:ok, 200, %{"count" => 1}} =
             Dawarich.Points.ApiWrites.bulk_destroy(ScratchRepo, actor, params, ctx)

    assert rows("SELECT count(*) FROM points WHERE id=$1", [point]) == [[0]]
    jobs = rows("SELECT worker FROM oban.oban_jobs")
    assert length(jobs) == 3
  end

  test "F3 digest batch eviction errors remain retryable" do
    user = stats_user()

    start_supervised!(
      {AfterCommitRegressionCacheConnection,
       %{parent: self(), key: "insights/yearly_digest/#{user}/2026/synthetic"}}
    )

    assert_raise MatchError, fn -> Dawarich.Points.DependentCaches.invalidate(user, 2026) end
    assert_received :digest_unlink_failed
  end

  test "F4 coexistence import visit deletion keeps cache until commit" do
    start_cache()
    System.delete_env("DAWARICH_RAILS")
    user = user!(%{"timezone" => "UTC"})
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:visits.suggest", :oban)

    [[visit]] =
      rows(
        "INSERT INTO visits(user_id,name,status,detection_version,duration,started_at,ended_at,created_at,updated_at) VALUES($1,'Original',0,1,60,'2026-01-01 00:00:00','2026-01-01 01:00:00',now(),now()) RETURNING id",
        [user]
      )

    key = "timeline_month_summary/#{user}/2026-01/UTC/pro/v3"
    {:ok, _} = Dawarich.Redis.cache_command(["SET", key, "original-cache"])

    {:error, :probe_rollback} =
      ScratchRepo.transaction(fn ->
        rows("DELETE FROM visits WHERE id=$1", [visit])

        Dawarich.Imports.DestroyEffects.visits!(%{repo: ScratchRepo, user: user}, [
          [visit, nil, ~N[2026-01-01 00:00:00], false]
        ])

        ScratchRepo.rollback(:probe_rollback)
      end)

    value = Dawarich.Redis.cache_command(["GET", key])
    assert rows("SELECT count(*) FROM visits WHERE id=$1", [visit]) == [[1]]
    assert value == {:ok, "original-cache"}
  end

  defp start_cache(), do: Enum.each(Dawarich.Redis.cache_child_specs(), &start_supervised!/1)

  defp arrival_args(user),
    do: %{"user_id" => user, "start_at" => @at, "end_at" => @at, "time_zone" => "UTC"}

  defp stats_args(user),
    do: %{"user_id" => user, "year" => 2026, "month" => 1, "time_zone" => "UTC"}

  defp stats_user() do
    user = user!(%{"timezone" => "UTC"})

    rows(
      "INSERT INTO stats(user_id,year,month,distance,sharing_uuid,created_at,updated_at) VALUES($1,2026,1,999,gen_random_uuid(),now(),now())",
      [user]
    )

    user
  end
end
