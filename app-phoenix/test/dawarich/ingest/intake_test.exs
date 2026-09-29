defmodule Dawarich.Ingest.IntakeTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Ingest.{Intake, Sources}

  defp payload(lon, lat, ts, extra \\ %{}),
    do:
      Map.merge(
        %{
          lonlat: "POINT(#{lon} #{lat})",
          timestamp: ts,
          tracker_id: "phone",
          raw_data: %{"a" => 1},
          motion_data: %{}
        },
        extra
      )

  defp ingest(user, payloads, opts \\ []),
    do: payloads |> Intake.prepare(user) |> Intake.write(user, opts)

  defp count(user), do: Repo.query!("SELECT points_count FROM users WHERE id = $1", [user]).rows

  test "writes the rows, counts inserts and queues the six commands in Rails' order" do
    user = user!()

    rows =
      ingest(user, [
        payload(13.4, 52.5, 1_788_930_000, %{battery: 80, altitude: 12.5, velocity: "3"}),
        payload(0, 0, 1)
      ])

    assert [%{xmax: "0", timestamp: 1_788_930_000, longitude: 13.4, latitude: 52.5}] = rows
    assert count(user) == [[1]]

    assert [
             ["points.tile_epoch", %{"user_id" => ^user, "timestamps" => [1_788_930_000]}],
             ["points.anomaly_filter", %{"start_at" => 1_788_930_000, "end_at" => 1_788_930_000}],
             ["tracks.realtime", %{"user_id" => ^user}],
             ["tracks.backfill", %{"timestamps" => [1_788_930_000, 1_788_930_000]}],
             ["visits.realtime", %{"user_id" => ^user}],
             [
               "points.live_broadcast",
               %{
                 "upserted" => [%{"id" => _}],
                 "payloads" => [%{"battery" => 80, "altitude" => 12.5, "velocity" => "3"}]
               }
             ]
           ] = commands()
  end

  test "a second write of the same point updates it, keeps created_at and the count, and resets archival" do
    user = user!()
    [%{id: id}] = ingest(user, [payload(13.4, 52.5, 1)])

    Repo.query!(
      "UPDATE points SET raw_data_archived = true, created_at = '2001-01-01', updated_at = '2001-01-01' WHERE id = $1",
      [id]
    )

    assert [%{id: ^id, xmax: xmax}] =
             ingest(user, [payload(13.4, 52.5, 1, %{raw_data: %{"a" => 2}})])

    refute xmax == "0"
    assert count(user) == [[1]]

    assert [[false, true]] =
             Repo.query!(
               "SELECT raw_data_archived, updated_at > created_at FROM points WHERE id = $1",
               [id]
             ).rows
  end

  test "drops unusable payloads and duplicates by Rails' dedup key" do
    user = user!()

    assert [_] =
             ingest(user, [
               payload(13.40, 52.5, 1),
               %{payload(13.4, 52.5, 1) | lonlat: "POINT(13.4 52.5)"},
               payload(0.0, 0.0, 2),
               %{payload(1, 1, 3) | lonlat: nil},
               %{payload(1, 1, 4) | timestamp: nil},
               nil
             ])
  end

  test "writes 1 000-point slices, each sorted by longitude, latitude and timestamp" do
    user = user!()
    rows = ingest(user, for(i <- 1_001..1, do: payload(10 + i / 10_000, 50, i)))
    {first, second} = Enum.split(rows, 1_000)

    assert Enum.map(first, & &1.timestamp) == Enum.to_list(2..1_001)
    assert Enum.map(second, & &1.timestamp) == [1]
  end

  test "one point_sources row per combo; no stamping while points.source_id is absent" do
    user = user!()
    ingest(user, [payload(1, 1, 1), payload(2, 2, 2)])

    assert [[1, 1]] =
             Repo.query!(
               "SELECT count(DISTINCT source_id), count(*) FILTER (WHERE source_id IS NULL) + 1 FROM points"
             ).rows

    Repo.query!("ALTER TABLE points DROP COLUMN source_id")
    Sources.forget()
    assert [_] = ingest(user, [payload(3, 3, 3)])
  end

  test "retries a transaction three times on contention, then gives up" do
    parent = self()

    deadlock = %Postgrex.Error{
      postgres: %{
        code: :deadlock_detected,
        severity: "ERROR",
        pg_code: "40P01",
        message: "deadlock detected"
      }
    }

    attempt = :counters.new(1, [])

    flaky = fn ->
      :counters.add(attempt, 1, 1)
      if :counters.get(attempt, 1) < 3, do: raise(deadlock), else: :done
    end

    assert Intake.retry(flaky, &send(parent, {:slept, &1}), 0) == :done
    assert_received {:slept, ms} when ms in 100..150

    assert_raise Postgrex.Error, fn ->
      Intake.retry(fn -> raise deadlock end, fn _ -> :ok end, 0)
    end
  end

  test "an empty batch touches nothing" do
    user = user!()
    assert ingest(user, [payload(0, 0, 1)]) == []
    assert commands() == []
  end

  defmodule DropAfterFirstSlice do
    def transaction(fun) do
      calls = Process.get(:a3_transactions, 0) + 1
      Process.put(:a3_transactions, calls)

      if calls > 1,
        do: raise(DBConnection.ConnectionError, "tcp recv: closed"),
        else: Dawarich.Repo.transaction(fun)
    end

    def query!(sql, params, opts), do: Dawarich.Repo.query!(sql, params, opts)
  end

  defmodule Raw do
    def query!(sql, params, _opts), do: Postgrex.query!(Process.get(:a3_conn), sql, params)
  end

  defp fault!(timestamp) do
    Repo.query!(
      "CREATE FUNCTION a3_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.timestamp = #{timestamp} THEN RAISE EXCEPTION 'a3 fault'; END IF; RETURN NEW; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a3_fault BEFORE INSERT ON points FOR EACH ROW EXECUTE FUNCTION a3_fault()"
    )
  end

  defp points(user),
    do:
      Repo.query!(
        "SELECT count(*), min(timestamp), max(timestamp) FROM points WHERE user_id = $1",
        [user]
      ).rows

  test "each slice commits on its own: a failure in slice 2 keeps slice 1 and its tile row, and nothing after it" do
    user = user!()
    before = count(user)
    fault!(1_001)

    assert_raise Postgrex.Error, fn ->
      ingest(user, for(i <- 1..1_001, do: payload(10 + i / 10_000, 50, i)))
    end

    assert points(user) == [[1_000, 1, 1_000]]
    assert count(user) == before
    assert [["points.tile_epoch", %{"user_id" => ^user, "timestamps" => stamps}]] = commands()
    assert Enum.sort(stamps) == Enum.to_list(1..1_000)
  end

  test "a connection drop after slice 1 committed is not retried: slice 1 stays, no counter, no other command" do
    user = user!()
    before = count(user)

    assert_raise DBConnection.ConnectionError, fn ->
      ingest(user, [payload(13.4, 52.5, 1)], repo: DropAfterFirstSlice)
    end

    assert Process.get(:a3_transactions) == 2
    assert points(user) == [[1, 1, 1]]
    assert count(user) == before
    assert [["points.tile_epoch", %{"timestamps" => [1]}]] = commands()
  end

  test "concurrent writers of one new combo share one point_sources row: the loser's first read misses, its second finds the winner" do
    config = Keyword.drop(Repo.config(), [:pool, :pool_size])
    {:ok, a} = Postgrex.start_link(config)
    {:ok, b} = Postgrex.start_link(config)
    {:ok, c} = Postgrex.start_link(config)
    tracker = "a3-race-#{System.unique_integer([:positive])}"
    combo = Sources.combo(%{tracker_id: tracker})

    on_exit(fn ->
      {:ok, d} = Postgrex.start_link(config)
      Postgrex.query!(d, "DELETE FROM point_sources WHERE tracker_id = $1", [tracker])
    end)

    Process.put(:a3_conn, a)
    Postgrex.query!(a, "BEGIN", [])
    winner = Sources.resolve(Raw, combo)

    loser =
      Task.async(fn ->
        Process.put(:a3_conn, b)
        Sources.resolve(Raw, combo)
      end)

    assert Enum.any?(1..1_000, fn _ ->
             Postgrex.query!(
               c,
               "SELECT 1 FROM pg_stat_activity WHERE wait_event_type = 'Lock' AND query LIKE '%INSERT INTO point_sources%'",
               []
             ).num_rows == 1
           end)

    Postgrex.query!(a, "COMMIT", [])
    assert Task.await(loser) == winner

    assert [[^winner, ^tracker]] =
             Postgrex.query!(
               c,
               "SELECT id, tracker_id FROM point_sources WHERE tracker_id = $1",
               [tracker]
             ).rows
  end

  test "an absent source_id is rechecked after 60 s, and the first write after it appears is stamped" do
    user = user!()
    Repo.query!("ALTER TABLE points DROP COLUMN source_id")
    Sources.forget()
    refute Sources.available?(Repo, 0)

    Repo.query!("ALTER TABLE points ADD COLUMN source_id bigint")
    refute Sources.available?(Repo, 59_999)
    assert Sources.available?(Repo, 60_000)

    [%{id: id}] = ingest(user, [payload(3, 3, 3)])

    assert [[^id, 3, "phone", source, source]] =
             Repo.query!(
               "SELECT p.id, p.timestamp, s.tracker_id, p.source_id, s.id FROM points p, point_sources s WHERE p.id = $1 AND s.tracker_id = 'phone'",
               [id]
             ).rows
  end

  test "`source_id` cache reset: the source cache lives for one request, so a point_sources row removed between requests is recreated" do
    user = user!()
    ingest(user, [payload(1, 1, 1)])
    Repo.query!("UPDATE points SET source_id = NULL")
    Repo.query!("DELETE FROM point_sources")

    [%{id: id}] = ingest(user, [payload(2, 2, 2)])

    assert [[^id, 2, "phone", source, source]] =
             Repo.query!(
               "SELECT p.id, p.timestamp, s.tracker_id, p.source_id, s.id FROM points p, point_sources s WHERE p.id = $1 AND s.tracker_id = 'phone'",
               [id]
             ).rows
  end
end
