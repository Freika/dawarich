defmodule Dawarich.ReleaseOperations.NullIslandTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperations.NullIsland

  @oban Dawarich.ReleaseOperations.NullIslandTest.Oban
  @island {:point, 0.01, 0.01}
  @earlier ~N[2020-01-01 00:00:00.000000]

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    :ok
  end

  test "the parent enqueues one child per live user with a null-island point" do
    flagged = Wave6Fixtures.user!()
    Wave6Fixtures.point!(flagged, %{"lonlat" => @island})
    clean = Wave6Fixtures.user!()
    Wave6Fixtures.point!(clean)
    deleted = Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})
    Wave6Fixtures.point!(deleted, %{"lonlat" => @island})
    id = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{"version" => 1, "event_id" => id, "cursor" => %{"after_id" => 0}},
      attempt: 1,
      max_attempts: 10
    }

    assert ReleaseOperations.run(ScratchRepo, @oban, NullIsland, job) == :ok

    assert rows("SELECT args FROM oban.oban_jobs") == [[%{"version" => 1, "user_id" => flagged}]]

    assert rows("SELECT status FROM phoenix.release_operations WHERE id = $1", [
             Ecto.UUID.dump!(id)
           ]) == [["completed"]]
  end

  test "a full parent page continues after its last user" do
    rows("""
    INSERT INTO users (email, status, points_count, settings, created_at, updated_at)
    SELECT 'island-' || g || '@example.test', 1, 1, '{}', now(), now() FROM generate_series(1, 1000) g
    """)

    rows("""
    INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at)
    SELECT id, 1577836800 + id, ST_SetSRID(ST_MakePoint(0.01, 0.01), 4326)::geography, now(), now()
    FROM users
    """)

    [[last]] = rows("SELECT max(id) FROM users")
    id = Ecto.UUID.generate()

    job = %Oban.Job{
      args: %{"version" => 1, "event_id" => id, "cursor" => %{"after_id" => 0}},
      attempt: 1,
      max_attempts: 10
    }

    assert ReleaseOperations.run(ScratchRepo, @oban, NullIsland, job) == :ok

    assert rows("SELECT count(*) FROM oban.oban_jobs WHERE args ? 'user_id'") == [[1000]]

    assert rows("SELECT args FROM oban.oban_jobs WHERE args ? 'cursor'") == [
             [%{"version" => 1, "operation_id" => id, "cursor" => %{"after_id" => last}}]
           ]

    assert rows("SELECT status FROM phoenix.release_operations") == [["running"]]
  end

  test "a child's flag stays invisible until its follow-up commits with it" do
    user = Wave6Fixtures.user!()
    island = Wave6Fixtures.point!(user, %{"lonlat" => @island})
    test = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!("LOCK TABLE phoenix.rails_commands")
          send(test, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held, 5_000

    child =
      Task.async(fn ->
        NullIsland.perform(%Oban.Job{args: %{"version" => 1, "user_id" => user}})
      end)

    Wave6Fixtures.await_waiter!("INSERT INTO phoenix.rails_commands%")
    assert rows("SELECT anomaly FROM points WHERE id = $1", [island]) == [[nil]]

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
    assert Task.await(child) == :ok

    assert rows("SELECT anomaly FROM points WHERE id = $1", [island]) == [[true]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]
  end

  test "a child flags that user's points within 5 km and writes the follow-up" do
    user = Wave6Fixtures.user!()
    island = Wave6Fixtures.point!(user, %{"lonlat" => @island, "updated_at" => @earlier})

    leipzig =
      Wave6Fixtures.point!(user, %{"lonlat" => {:point, 12.37, 51.34}, "updated_at" => @earlier})

    other = Wave6Fixtures.user!()
    foreign = Wave6Fixtures.point!(other, %{"lonlat" => @island, "updated_at" => @earlier})

    assert NullIsland.perform(%Oban.Job{args: %{"version" => 1, "user_id" => user}}) == :ok

    assert rows("SELECT id, anomaly, updated_at > $1 FROM points ORDER BY id", [@earlier]) == [
             [island, true, true],
             [leipzig, nil, false],
             [foreign, nil, false]
           ]

    assert rows("SELECT kind, payload FROM phoenix.rails_commands") == [
             ["release_null_island_follow_up", %{"user_id" => user}]
           ]
  end

  test "a deleted user's child does nothing" do
    user = Wave6Fixtures.user!(%{"deleted_at" => NaiveDateTime.utc_now()})
    Wave6Fixtures.point!(user, %{"lonlat" => @island})

    assert NullIsland.perform(%Oban.Job{args: %{"version" => 1, "user_id" => user}}) == :ok

    assert rows("SELECT anomaly FROM points") == [[nil]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "the predicate equals Rails'" do
    assert NullIsland.predicate() == Wave6Fixtures.load!("sql_fragments")["null_island"]
  end

  test "decodes version 1 payloads exactly" do
    assert NullIsland.args_from_command(1, %{"user_id" => nil}) ==
             {:ok, %{"version" => 1, "cursor" => %{"after_id" => 0}}}

    assert NullIsland.args_from_command(1, %{"user_id" => 5}) ==
             {:ok, %{"version" => 1, "user_id" => 5}}

    for invalid <- [%{}, %{"user_id" => "5"}, %{"user_id" => 5, "extra" => 1}] do
      assert NullIsland.args_from_command(1, invalid) == {:error, "invalid_payload"}
    end

    assert NullIsland.args_from_command(2, %{"user_id" => nil}) == {:error, "unsupported_version"}
  end
end
