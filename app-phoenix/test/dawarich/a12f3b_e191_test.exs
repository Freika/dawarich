defmodule Dawarich.A12f3bE191Test do
  use Dawarich.JobsCase

  alias Dawarich.{ReleaseJobs, ReleaseOperations, Wave6Fixtures}
  alias Dawarich.Jobs.{Drain, Ownership}

  @oban __MODULE__.Oban

  setup do
    start_oban(@oban)
    Wave6Fixtures.reset!()
    old = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
    end)

    Ownership.put!(ScratchRepo, "command:mail.family_lapse", :oban)
    :ok
  end

  @tag a12f3b_case: "E191a"
  test "E191 native source shapes reach their terminal effects" do
    eligible = Wave6Fixtures.user!(%{"plan" => 2, "active_until" => ~N[2027-01-01 00:00:00]})
    Wave6Fixtures.user!(%{"plan" => 1})
    deleted = Wave6Fixtures.user!(%{"plan" => 2, "deleted_at" => ~N[2026-01-01 00:00:00]})

    assert {:ok, worker, args} =
             ReleaseJobs.decode("DataMigrations::BackfillFamiliesForFamilyPlanJob", [])

    assert {:ok, _} = Ecto.UUID.cast(args["operation_id"])
    assert {:ok, Map.drop(args, ["operation_id"])} == worker.args_from_command(1, args["cursor"])
    assert worker.args_from_command(99, args["cursor"]) == {:error, "unsupported_version"}

    assert worker.args_from_command(1, %{"_aj_globalid" => "gid://dawarich/User/42"}) ==
             {:error, "invalid_payload"}

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args}) == :ok

    assert [[child]] = rows("SELECT args FROM oban.oban_jobs")
    assert child["user_id"] == eligible
    refute child["user_id"] == deleted
    assert Dawarich.Families.AutoCreateWorker.run(ScratchRepo, child) == :ok
    assert [[family]] = rows("SELECT id FROM families WHERE creator_id=$1", [eligible])

    assert rows("SELECT user_id,role FROM family_memberships WHERE family_id=$1", [family]) == [
             [eligible, 0]
           ]

    member = Wave6Fixtures.user!(%{"plan" => 0, "status" => 0, "active_until" => nil})

    rows(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
      [family, member]
    )

    assert {:ok, worker, args} =
             ReleaseJobs.decode("DataMigrations::BackfillFamilyMemberEntitlementsJob", [])

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args}) == :ok

    assert rows("SELECT plan,status,active_until FROM users WHERE id=$1", [member]) == [
             [1, 1, ~N[2027-01-01 00:00:00.000000]]
           ]

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]

    assert rows("SELECT count(*) FROM phoenix.release_operations WHERE status <> 'completed'") ==
             [[0]]

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args}) == :ok

    rows("UPDATE users SET active_until='2025-01-01' WHERE id=$1", [eligible])

    assert {:ok, worker, expired} =
             ReleaseJobs.decode("DataMigrations::BackfillFamilyMemberEntitlementsJob", [])

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: expired}) == :ok

    assert rows(
             "SELECT plan,status,settings->'family'->>'plan_lapse_notified_at' IS NOT NULL FROM users WHERE id=$1",
             [member]
           ) == [[0, 0, true]]

    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    for class <-
          ~w(DataMigrations::BackfillCountryNameJob DataMigrations::DedupeTracksForUniqueIndexJob DataMigrations::MigratePlacesLonlatJob DataMigrations::PrefillPointsCounterCacheJob) do
      assert ReleaseJobs.decode(class, []) == {:error, :unknown_class}
    end

    reset!(ScratchRepo)

    members =
      for _ <- 1..2 do
        owner = Wave6Fixtures.user!(%{"plan" => 2, "active_until" => ~N[2027-01-01 00:00:00]})

        family =
          Wave6Fixtures.insert!("families", %{
            "creator_id" => owner,
            "name" => "Release family",
            "created_at" => ~N[2026-01-01 00:00:00],
            "updated_at" => ~N[2026-01-01 00:00:00]
          })

        member = Wave6Fixtures.user!(%{"plan" => 0, "status" => 0})

        rows(
          "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
          [family, member]
        )

        member
      end

    [first, second] = members

    rows(
      "ALTER TABLE users ADD CONSTRAINT e191_member_failure CHECK(id <> #{second} OR plan <> 1)"
    )

    try do
      assert {:ok, worker, args} =
               ReleaseJobs.decode("DataMigrations::BackfillFamilyMemberEntitlementsJob", [])

      assert_raise Postgrex.Error, fn ->
        ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args})
      end

      assert rows("SELECT plan FROM users WHERE id=$1", [first]) == [[1]]
      assert rows("SELECT plan FROM users WHERE id=$1", [second]) == [[0]]
      assert rows("SELECT status FROM phoenix.release_operations") == [["running"]]
    after
      rows("ALTER TABLE users DROP CONSTRAINT e191_member_failure")
    end
  end

  @tag a12f3b_case: "E191b"
  test "E191 accepted children prevent premature completion" do
    Wave6Fixtures.user!(%{"plan" => 2})

    assert {:ok, worker, args} =
             ReleaseJobs.decode("DataMigrations::BackfillFamiliesForFamilyPlanJob", [])

    rows(
      "ALTER TABLE oban.oban_jobs ADD CONSTRAINT e191_child_failure CHECK(worker <> 'Dawarich.Families.AutoCreateWorker')"
    )

    try do
      assert_raise Ecto.ConstraintError, fn ->
        ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args})
      end

      assert rows("SELECT status FROM phoenix.release_operations") == [["running"]]
      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert "release_pending" in Drain.status(ScratchRepo).binary_reasons
    after
      rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT e191_child_failure")
    end

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args}) == :ok
    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
    assert "incomplete_oban" in Drain.status(ScratchRepo).binary_reasons
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    reset!(ScratchRepo)

    rows(
      "INSERT INTO users(email,plan,settings,created_at,updated_at) SELECT 'release-family-'||n||'@example.test',2,'{}',now(),now() FROM generate_series(1,501) AS n"
    )

    assert {:ok, worker, args} =
             ReleaseJobs.decode("DataMigrations::BackfillFamiliesForFamilyPlanJob", [])

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args}) == :ok

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Families.AutoCreateWorker'"
           ) == [[500]]

    assert [[next]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.ReleaseJobs.FamilyBackfill'"
             )

    assert next["operation_id"] == args["operation_id"]
    assert next["cursor"]["after_id"] > 0
    assert next["cursor"]["time_zone"] == args["cursor"]["time_zone"]
    assert rows("SELECT status FROM phoenix.release_operations") == [["running"]]
    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: args}) == :ok

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Families.AutoCreateWorker'"
           ) == [[500]]

    assert ReleaseOperations.run(ScratchRepo, @oban, worker, %Oban.Job{args: next}) == :ok

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Families.AutoCreateWorker'"
           ) == [[501]]

    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
    assert "incomplete_oban" in Drain.status(ScratchRepo).binary_reasons
  end
end
