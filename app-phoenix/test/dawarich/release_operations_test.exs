defmodule Dawarich.ReleaseOperationsTest.Counter do
  use Oban.Worker, queue: :maintenance

  alias Dawarich.ReleaseOperations

  def command_type, do: "release.counter"

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  def step(repo, %{cursor: %{"user_id" => user_id, "n" => n, "limit" => limit}} = op) do
    ReleaseOperations.commit(repo, op, fn ->
      repo.query!("UPDATE users SET points_count = points_count + 1 WHERE id = $1", [user_id])
      if Process.get(:raise_after_write), do: raise("boom")

      if n + 1 >= limit,
        do: :done,
        else: {%{"user_id" => user_id, "n" => n + 1, "limit" => limit}, 0}
    end)
  end
end

defmodule Dawarich.ReleaseOperationsTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.{ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseOperationsTest.Counter

  @oban Dawarich.ReleaseOperationsTest.Oban

  setup do
    Wave6Fixtures.reset!()
    start_oban(@oban)
    %{user: Wave6Fixtures.user!()}
  end

  test "a first run creates the operation, writes, advances and enqueues the next page", %{
    user: user
  } do
    id = Ecto.UUID.generate()

    assert run(%{"version" => 1, "event_id" => id, "cursor" => cursor(user, 0, 3)}) == :ok

    assert points_count(user) == 1
    assert operation(id) == [[cursor(user, 1, 3), "running"]]

    assert jobs() == [
             [%{"version" => 1, "operation_id" => id, "cursor" => cursor(user, 1, 3)}]
           ]
  end

  test "a replayed first job does nothing", %{user: user} do
    args = %{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => cursor(user, 0, 3)}

    assert run(args) == :ok
    assert run(args) == :ok

    assert points_count(user) == 1
    assert length(jobs()) == 1
  end

  test "the last page completes and enqueues nothing", %{user: user} do
    id = Ecto.UUID.generate()

    assert run(%{"version" => 1, "event_id" => id, "cursor" => cursor(user, 0, 1)}) == :ok

    assert rows(
             "SELECT status, completed_at IS NOT NULL FROM phoenix.release_operations WHERE id = $1",
             [Ecto.UUID.dump!(id)]
           ) == [["completed", true]]

    assert jobs() == []
  end

  test "a raise after the write rolls back the write, the cursor and the successor", %{
    user: user
  } do
    id = Ecto.UUID.generate()
    Process.put(:raise_after_write, true)

    assert_raise RuntimeError, "boom", fn ->
      run(%{"version" => 1, "event_id" => id, "cursor" => cursor(user, 0, 3)})
    end

    assert points_count(user) == 0
    assert operation(id) == [[cursor(user, 0, 3), "running"]]
    assert jobs() == []
  end

  test "a page racing an advance on another connection rolls back", %{user: user} do
    id = Ecto.UUID.generate()

    running!(id, cursor(user, 0, 3))
    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!(
            "SELECT 1 FROM phoenix.release_operations WHERE id = $1 FOR UPDATE",
            [Ecto.UUID.dump!(id)]
          )

          send(parent, :locked)

          receive do
            :advance ->
              ScratchRepo.query!(
                "UPDATE phoenix.release_operations SET cursor = $2 WHERE id = $1",
                [Ecto.UUID.dump!(id), cursor(user, 1, 3)]
              )
          end
        end)
      end)

    assert_receive :locked, 5_000

    page =
      Task.async(fn ->
        run(%{"version" => 1, "operation_id" => id, "cursor" => cursor(user, 0, 3)})
      end)

    await_advance_waiter!(System.monotonic_time(:millisecond) + 5_000)
    send(holder.pid, :advance)

    assert {:ok, _} = Task.await(holder)
    assert Task.await(page) == :ok
    assert points_count(user) == 0
    assert operation(id) == [[cursor(user, 1, 3), "running"]]
    assert jobs() == []
  end

  test "a completed operation ignores a late page", %{user: user} do
    args = %{"version" => 1, "event_id" => Ecto.UUID.generate(), "cursor" => cursor(user, 0, 1)}

    assert run(args) == :ok
    assert run(args) == :ok

    assert points_count(user) == 1
    assert jobs() == []
  end

  test "the final failed attempt fails the operation; resume re-enqueues from its cursor", %{
    user: user
  } do
    id = Ecto.UUID.generate()
    Process.put(:raise_after_write, true)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert_raise RuntimeError, fn ->
          run(%{"version" => 1, "event_id" => id, "cursor" => cursor(user, 0, 3)}, 10, 10)
        end
      end)

    assert log =~ "resume with dawarich jobs resume #{id}"

    assert rows("SELECT status, error FROM phoenix.release_operations WHERE id = $1", [
             Ecto.UUID.dump!(id)
           ]) == [["failed", "boom"]]

    assert {:ok, _} = resume(id)
    assert operation(id) == [[cursor(user, 0, 3), "running"]]

    assert jobs() == [
             [%{"version" => 1, "operation_id" => id, "cursor" => cursor(user, 0, 3)}]
           ]
  end

  test "resume refuses a completed or unknown operation", %{user: user} do
    id = Ecto.UUID.generate()
    assert run(%{"version" => 1, "event_id" => id, "cursor" => cursor(user, 0, 1)}) == :ok

    assert resume(id) == {:error, :not_resumable}
    assert resume(Ecto.UUID.generate()) == {:error, :not_resumable}
    assert operation(id) == [[cursor(user, 0, 1), "completed"]]
    assert jobs() == []
  end

  test "resume refuses a running operation while a job for it is live", %{user: user} do
    for {key, state} <- [
          {"operation_id", "available"},
          {"operation_id", "scheduled"},
          {"operation_id", "executing"},
          {"operation_id", "retryable"},
          {"operation_id", "suspended"},
          {"event_id", "executing"}
        ] do
      id = Ecto.UUID.generate()
      running!(id, cursor(user, 0, 3))
      job!(%{"version" => 1, key => id, "cursor" => cursor(user, 0, 3)}, state)

      assert resume(id) == {:error, :not_resumable}, "#{key} #{state}"
      assert operation(id) == [[cursor(user, 0, 3), "running"]]
    end

    assert length(jobs()) == 6
  end

  test "resume re-enqueues a running operation whose job is no longer live", %{user: user} do
    for state <- ~w(discarded cancelled) do
      id = Ecto.UUID.generate()
      running!(id, cursor(user, 1, 3))
      job!(%{"version" => 1, "operation_id" => id, "cursor" => cursor(user, 1, 3)}, state)

      for key <- ~w(operation_id event_id),
          do: job!(%{"version" => 1, key => Ecto.UUID.generate(), "cursor" => %{}}, "executing")

      assert {:ok, _} = resume(id), state
      assert operation(id) == [[cursor(user, 1, 3), "running"]]

      assert rows("SELECT args FROM oban.oban_jobs WHERE state IN ('available', 'scheduled')") ==
               [
                 [%{"version" => 1, "operation_id" => id, "cursor" => cursor(user, 1, 3)}]
               ]

      rows("DELETE FROM oban.oban_jobs")
    end
  end

  test "unsupported versions and missing ids cancel", %{user: user} do
    v2 = %{"version" => 2, "event_id" => Ecto.UUID.generate(), "cursor" => cursor(user, 0, 3)}

    assert run(v2) == {:cancel, :unsupported_version}

    assert run(%{"version" => 1, "cursor" => cursor(user, 0, 3)}) ==
             {:cancel, :unsupported_version}

    assert points_count(user) == 0
    assert rows("SELECT count(*) FROM phoenix.release_operations") == [[0]]
  end

  test "no_payload decodes only the empty payload at version 1" do
    assert ReleaseOperations.no_payload(1, %{}) == {:ok, %{"version" => 1}}
    assert ReleaseOperations.no_payload(1, %{"x" => 1}) == {:error, "invalid_payload"}
    assert ReleaseOperations.no_payload(2, %{}) == {:error, "unsupported_version"}
  end

  defp run(args, attempt \\ 1, max_attempts \\ 10) do
    job = %Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}
    ReleaseOperations.run(ScratchRepo, @oban, Counter, job)
  end

  defp cursor(user, n, limit), do: %{"user_id" => user, "n" => n, "limit" => limit}

  defp points_count(user) do
    [[count]] = rows("SELECT points_count FROM users WHERE id = $1", [user])
    count
  end

  defp operation(id),
    do:
      rows("SELECT cursor, status FROM phoenix.release_operations WHERE id = $1", [
        Ecto.UUID.dump!(id)
      ])

  defp jobs, do: rows("SELECT args FROM oban.oban_jobs ORDER BY id")

  defp resume(id),
    do:
      ReleaseOperations.resume(ScratchRepo, @oban, id, fn "release.counter" -> {:ok, Counter} end)

  defp running!(id, cursor),
    do:
      rows(
        "INSERT INTO phoenix.release_operations (id, command_type, cursor) VALUES ($1, 'release.counter', $2)",
        [Ecto.UUID.dump!(id), cursor]
      )

  defp job!(args, state) do
    job = Oban.insert!(@oban, Counter.new(args))

    rows("UPDATE oban.oban_jobs SET state = $2::text::oban.oban_job_state WHERE id = $1", [
      job.id,
      state
    ])
  end

  defp await_advance_waiter!(deadline) do
    waiting =
      rows("""
      SELECT count(DISTINCT l.pid) FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
      WHERE NOT l.granted AND a.datname = current_database()
        AND a.query LIKE 'UPDATE phoenix.release_operations SET cursor%'
      """)

    cond do
      waiting == [[1]] ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("the page never waited on the operation row")

      true ->
        :erlang.yield()
        await_advance_waiter!(deadline)
    end
  end
end
