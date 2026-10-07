defmodule Dawarich.ReleaseJobs.CloudFamilyAdmissionTest do
  use Dawarich.JobsCase

  alias Dawarich.{ReleaseJobs, Wave6Fixtures}
  alias Dawarich.ReleaseJobs.FamilyBackfill
  alias Dawarich.Jobs.Dispatch
  alias Dawarich.Release.CloudJobs

  @oban __MODULE__.Oban
  @classes ~w(DataMigrations::BackfillFamiliesForFamilyPlanJob DataMigrations::BackfillFamilyMemberEntitlementsJob)
  @max_id 9_223_372_036_854_775_807

  setup do
    old = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    on_exit(fn ->
      if old, do: System.put_env("SELF_HOSTED", old), else: System.delete_env("SELF_HOSTED")
    end)

    start_oban(@oban)
    owner = Wave6Fixtures.user!(%{"plan" => 2, "active_until" => ~N[2099-01-01 00:00:00]})

    family =
      Wave6Fixtures.insert!("families", %{
        "creator_id" => owner,
        "name" => "Synthetic family",
        "created_at" => ~N[2020-01-01 00:00:00],
        "updated_at" => ~N[2020-01-01 00:00:00]
      })

    member = Wave6Fixtures.user!(%{"plan" => 0, "status" => 0})

    rows(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
      [family, member]
    )

    Wave6Fixtures.user!(%{"plan" => 2})
    %{member: member}
  end

  test "E-R1 complete outer envelopes refuse unknown fields and every malformed identity before real effects",
       %{member: member} do
    observations =
      for class <- @classes do
        {:ok, FamilyBackfill, args} = ReleaseJobs.decode(class, [])
        event = Ecto.UUID.generate()
        combined = Map.put(args, "event_id", event)

        malformed = [
          Map.put(args, "unexpected", true),
          Map.put(combined, "event_id", "invalid-id"),
          Map.put(combined, "event_id", nil),
          Map.put(combined, "event_id", 42),
          Map.put(args, "operation_id", "abcdefghijklmnop"),
          Map.put(combined, "event_id", "abcdefghijklmnop"),
          Map.put(combined, "operation_id", "invalid-id"),
          Map.put(combined, "operation_id", nil),
          Map.delete(args, "operation_id"),
          Map.delete(args, "version"),
          Map.delete(args, "cursor"),
          Map.put(args, :unexpected, true),
          ["invalid"],
          nil,
          42
        ]

        results =
          for invalid <- malformed do
            {:error, observation} =
              ScratchRepo.transaction(fn ->
                before = effects(member)
                result = admit(invalid)
                ScratchRepo.rollback({result, effects(member) == before})
              end)

            observation
          end

        assert results == List.duplicate({{:cancel, :invalid_payload}, true}, length(malformed))

        for valid <- [
              args,
              Map.delete(combined, "operation_id"),
              combined,
              Map.update!(combined, "operation_id", &String.upcase/1)
            ] do
          {:error, :verified} =
            ScratchRepo.transaction(fn ->
              assert run(valid) == :ok
              assert run(valid) == :ok
              id = String.downcase(valid["operation_id"] || valid["event_id"])

              assert rows("SELECT status FROM phoenix.release_operations WHERE id=$1", [
                       Ecto.UUID.dump!(id)
                     ]) == [["completed"]]

              if args["cursor"]["phase"] == "families" do
                assert rows("SELECT count(*) FROM oban.oban_jobs") == [[1]]
              else
                assert rows("SELECT plan,status FROM users WHERE id=$1", [member]) == [[1, 1]]
              end

              ScratchRepo.rollback(:verified)
            end)
        end

        :verified
      end

    assert observations == [:verified, :verified]
  end

  test "E-R2 bigint cursor boundaries reject before operation child or typed dispatch publication",
       %{member: member} do
    for class <- @classes do
      {:ok, FamilyBackfill, args} = ReleaseJobs.decode(class, [])
      invalid = put_in(args, ["cursor", "after_id"], @max_id + 1)
      assert FamilyBackfill.args_from_command(1, invalid["cursor"]) == {:error, "invalid_payload"}
      before = effects(member)
      assert admit(invalid) == {:cancel, :invalid_payload}
      assert effects(member) == before
      event = outbox!(command_type: "release.family_backfill", payload: invalid["cursor"])
      before_dispatch = effects(member)
      assert Dispatch.run(repo: ScratchRepo, oban: @oban) == %{quarantined: 1}

      assert rows("SELECT state,error_code FROM job_outbox WHERE event_id=$1", [
               Ecto.UUID.dump!(event)
             ]) == [["quarantined", "invalid_payload"]]

      assert effects(member) == before_dispatch

      for id <- [0, @max_id] do
        cursor = Map.put(args["cursor"], "after_id", id)
        assert {:ok, _} = FamilyBackfill.args_from_command(1, cursor)
      end

      assert run(put_in(args, ["cursor", "after_id"], @max_id)) == :ok
    end
  end

  test "E-R2 execution exceptions settle a failed cursor and a real retry completes both phases" do
    for {class, phase} <- Enum.zip(@classes, ["families", "entitlements"]) do
      {:ok, FamilyBackfill, args} = ReleaseJobs.decode(class, [])

      constraint =
        if phase == "families",
          do:
            "ALTER TABLE oban.oban_jobs ADD CONSTRAINT family_admission_failure CHECK(worker <> 'Dawarich.Families.AutoCreateWorker')",
          else: "ALTER TABLE users ADD CONSTRAINT family_admission_failure CHECK(plan <> 1)"

      table = if phase == "families", do: "oban.oban_jobs", else: "users"
      error = if phase == "families", do: Ecto.ConstraintError, else: Postgrex.Error
      rows(constraint)

      try do
        ExUnit.CaptureLog.capture_log(fn ->
          assert_raise error, fn -> run(args) end
        end)

        assert rows("SELECT cursor,status FROM phoenix.release_operations WHERE id=$1", [
                 Ecto.UUID.dump!(args["operation_id"])
               ]) == [[args["cursor"], "failed"]]

        refute CloudJobs.ready?(ScratchRepo)
        assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      after
        rows("ALTER TABLE #{table} DROP CONSTRAINT family_admission_failure")
      end

      assert run(args, 2) == :ok

      assert rows("SELECT status FROM phoenix.release_operations WHERE id=$1", [
               Ecto.UUID.dump!(args["operation_id"])
             ]) == [["completed"]]

      if phase == "entitlements",
        do: assert(rows("SELECT count(*) FROM users WHERE plan=1") == [[1]])

      assert run(args, 3) == :ok
      if phase == "families", do: rows("DELETE FROM oban.oban_jobs")
    end
  end

  defp effects(member) do
    {rows("SELECT count(*) FROM phoenix.release_operations"),
     rows("SELECT count(*) FROM oban.oban_jobs"), rows("SELECT count(*) FROM notifications"),
     rows("SELECT count(*) FROM job_outbox"),
     rows("SELECT access_until FROM families ORDER BY id"),
     rows("SELECT plan,status,active_until FROM users WHERE id=$1", [member])}
  end

  defp admit(args) do
    run(args)
  rescue
    error -> {:raised, error.__struct__}
  end

  defp run(args, attempt \\ 1),
    do:
      FamilyBackfill.perform(%Oban.Job{
        args: args,
        conf: Oban.config(@oban),
        attempt: attempt,
        max_attempts: 26
      })
end
