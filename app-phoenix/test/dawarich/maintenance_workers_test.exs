defmodule Dawarich.MaintenanceWorkersTest do
  use Dawarich.ScratchCase, async: true, group: :scratch_db

  alias Dawarich.Families.{InvitationCleanupWorker, LocationRequestExpiryWorker}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Users.PointsCounterCorrectionWorker

  @workers [InvitationCleanupWorker, LocationRequestExpiryWorker, PointsCounterCorrectionWorker]
  @now ~N[2026-09-26 12:00:00]

  setup do
    scratch_sql!("""
    CREATE TABLE family_invitations (id bigserial PRIMARY KEY, status integer NOT NULL DEFAULT 0,
      expires_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE TABLE family_location_requests (id bigserial PRIMARY KEY, status integer NOT NULL DEFAULT 0,
      expires_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL);
    CREATE TABLE users (id bigserial PRIMARY KEY, status integer DEFAULT 0, deleted_at timestamp(6),
      points_count integer NOT NULL DEFAULT 0, updated_at timestamp(6) NOT NULL);
    CREATE TABLE points (id bigserial PRIMARY KEY, user_id bigint);
    INSERT INTO family_invitations (status, expires_at, updated_at)
      VALUES (0, '2026-09-26 11:00:00', '2026-09-25 00:00:00');
    INSERT INTO family_location_requests (status, expires_at, updated_at)
      VALUES (0, '2026-09-26 11:00:00', '2026-09-25 00:00:00');
    INSERT INTO users (status, points_count, updated_at)
      SELECT 1, 7, '2026-09-01 00:00:00' FROM generate_series(1, 5);
    """)

    for worker <- @workers, do: Ownership.put!(ScratchRepo, worker.key(), :oban)
    :ok
  end

  test "each worker changes nothing and cancels while Sidekiq owns its cron entry" do
    for worker <- @workers, do: Ownership.put!(ScratchRepo, worker.key(), :sidekiq)

    assert Enum.map(@workers, &run/1) == List.duplicate({:cancel, :not_owner}, 3)
    assert snapshot() == %{invitations: [0], requests: [0], counts: [7, 7, 7, 7, 7]}
  end

  test "each worker applies its sweep while Oban owns its cron entry" do
    assert Enum.map(@workers, &run/1) == [:ok, :ok, :ok]
    assert snapshot() == %{invitations: [2], requests: [3], counts: [0, 0, 0, 0, 0]}
  end

  test "the points sweep stops at the first batch after ownership moves to Sidekiq" do
    scratch_sql!("""
    CREATE FUNCTION hand_back() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE phoenix.job_owners SET owner = 'sidekiq' WHERE key = '#{PointsCounterCorrectionWorker.key()}';
      RETURN NEW;
    END $$;
    CREATE TRIGGER hand_back AFTER UPDATE ON users FOR EACH ROW WHEN (NEW.id = 2)
      EXECUTE FUNCTION hand_back();
    """)

    assert PointsCounterCorrectionWorker.run(ScratchRepo, 2) == {:cancel, :not_owner}
    assert snapshot().counts == [0, 0, 7, 7, 7]
  end

  test "a failure inside a points batch rolls that batch back and the next run converges" do
    scratch_sql!("""
    CREATE FUNCTION boom() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'injected'; END $$;
    CREATE TRIGGER boom BEFORE UPDATE ON users FOR EACH ROW WHEN (NEW.id = 4)
      EXECUTE FUNCTION boom();
    """)

    assert_raise Postgrex.Error, ~r/injected/, fn ->
      PointsCounterCorrectionWorker.run(ScratchRepo, 2)
    end

    assert snapshot().counts == [0, 0, 7, 7, 7]

    scratch_sql!("DROP TRIGGER boom ON users")

    assert PointsCounterCorrectionWorker.run(ScratchRepo, 2) == :ok
    assert snapshot().counts == [0, 0, 0, 0, 0]
  end

  test "two points sweeps at once leave the counts one sweep leaves" do
    tasks =
      for _ <- 1..2, do: Task.async(fn -> PointsCounterCorrectionWorker.run(ScratchRepo, 2) end)

    assert Task.await_many(tasks, :infinity) == [:ok, :ok]
    assert snapshot().counts == [0, 0, 0, 0, 0]
  end

  test "every worker runs on the maintenance queue with three attempts and one incomplete job" do
    for worker <- @workers do
      %{changes: changes} = worker.new(%{})

      assert changes.queue == "maintenance"
      assert changes.max_attempts == 3
      assert changes.unique.period == :infinity
      assert changes.unique.states == Oban.Job.unique_states(:incomplete)
    end
  end

  defp run(PointsCounterCorrectionWorker), do: PointsCounterCorrectionWorker.run(ScratchRepo, 2)
  defp run(worker), do: worker.run(ScratchRepo, @now)

  defp snapshot do
    %{
      invitations: column("SELECT status FROM family_invitations ORDER BY id"),
      requests: column("SELECT status FROM family_location_requests ORDER BY id"),
      counts: column("SELECT points_count FROM users ORDER BY id")
    }
  end

  defp column(sql), do: ScratchRepo.query!(sql, [], log: false).rows |> List.flatten()
end
