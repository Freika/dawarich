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
        event = outbox!(command_type: FamilyBackfill.command_type(), payload: args["cursor"])

        assert %{dispatched: 1} =
                 Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo))

        rows("DELETE FROM oban.oban_jobs")
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
              Map.update!(combined, "operation_id", &String.upcase/1),
              Map.update!(combined, "event_id", &String.upcase/1)
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

  test "E-R1-F foreign existing event and operation bindings refuse before either phase changes effects",
       %{member: member} do
    observations =
      for class <- @classes,
          kind <- [
            :foreign_event,
            :uppercase_event,
            :event_kind,
            :event_payload,
            :event_state,
            :missing_event,
            :foreign_operation,
            :operation_kind,
            :operation_zone,
            :operation_cursor,
            :enqueued_state,
            :enqueued_operation
          ] do
        {:ok, FamilyBackfill, args} = ReleaseJobs.decode(class, [])

        {:error, observation} =
          ScratchRepo.transaction(fn ->
            event = outbox!(command_type: FamilyBackfill.command_type(), payload: args["cursor"])

            assert %{dispatched: 1} =
                     Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo))

            rows("DELETE FROM oban.oban_jobs")
            combined = Map.put(args, "event_id", event)

            {invalid, job_id} =
              case kind do
                kind when kind in [:foreign_event, :uppercase_event] ->
                  foreign =
                    outbox!(
                      command_type: "families.auto_create",
                      payload: %{"user_id" => member, "time_zone" => "Europe/Berlin"}
                    )

                  foreign = if kind == :uppercase_event, do: String.upcase(foreign), else: foreign
                  {Map.put(combined, "event_id", foreign), nil}

                :missing_event ->
                  {Map.put(combined, "event_id", Ecto.UUID.generate()), nil}

                kind when kind in [:event_kind, :event_payload, :event_state] ->
                  cursor = args["cursor"]
                  other = if cursor["phase"] == "families", do: "entitlements", else: "families"

                  payload =
                    if kind == :event_kind,
                      do: %{cursor | "phase" => other},
                      else: %{cursor | "after_id" => 1}

                  if kind == :event_state,
                    do:
                      rows("UPDATE job_outbox SET state='quarantined' WHERE event_id=$1", [
                        Ecto.UUID.dump!(event)
                      ]),
                    else:
                      rows("UPDATE job_outbox SET payload=$2 WHERE event_id=$1", [
                        Ecto.UUID.dump!(event),
                        payload
                      ])

                  {combined, nil}

                kind ->
                  cursor = args["cursor"]
                  other = if cursor["phase"] == "families", do: "entitlements", else: "families"

                  foreign_cursor =
                    case kind do
                      :operation_kind -> %{cursor | "phase" => other}
                      :operation_zone -> %{cursor | "time_zone" => "UTC"}
                      :operation_cursor -> %{cursor | "after_id" => nil}
                      _ -> cursor
                    end

                  type =
                    if kind == :foreign_operation,
                      do: "release.altitude",
                      else: FamilyBackfill.command_type()

                  rows(
                    "INSERT INTO phoenix.release_operations(id,command_type,cursor,status) VALUES($1,$2,$3,$4)",
                    [Ecto.UUID.dump!(args["operation_id"]), type, foreign_cursor, "running"]
                  )

                  if kind in [:enqueued_operation, :enqueued_state] do
                    job = Oban.insert!(@oban, FamilyBackfill.new(args))
                    foreign = Ecto.UUID.generate()

                    rows(
                      "INSERT INTO phoenix.release_operations(id,command_type,cursor) VALUES($1,$2,$3)",
                      [Ecto.UUID.dump!(foreign), type, cursor]
                    )

                    if kind == :enqueued_state do
                      rows("UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", [job.id])
                      {args, job.id}
                    else
                      {Map.put(args, "operation_id", foreign), job.id}
                    end
                  else
                    {combined, nil}
                  end
              end

            before = binding_effects(member)
            result = admit_job(invalid, job_id)

            ScratchRepo.rollback(
              {kind, args["cursor"]["phase"], result, binding_effects(member) == before}
            )
          end)

        observation
      end

    assert Enum.all?(observations, fn {_, _, result, unchanged} ->
             result == {:cancel, :invalid_payload} and unchanged
           end),
           inspect(observations)
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

      assert Dispatch.run(repo: ScratchRepo, oban: @oban, now: db_now(ScratchRepo)) == %{
               quarantined: 1
             }

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

  defp binding_effects(member) do
    {effects(member),
     rows(
       "SELECT id,command_type,cursor,status,error,inserted_at,updated_at,completed_at FROM phoenix.release_operations ORDER BY id"
     ),
     rows(
       "SELECT event_id,command_type,command_version,payload,state,oban_job_id,error_code,dispatched_at FROM job_outbox ORDER BY event_id"
     )}
  end

  defp effects(member) do
    {rows("SELECT count(*) FROM phoenix.release_operations"),
     rows("SELECT count(*) FROM oban.oban_jobs"), rows("SELECT count(*) FROM notifications"),
     rows("SELECT count(*) FROM job_outbox"),
     rows("SELECT access_until FROM families ORDER BY id"),
     rows("SELECT plan,status,active_until FROM users WHERE id=$1", [member])}
  end

  defp admit_job(args, id) do
    FamilyBackfill.perform(%Oban.Job{
      id: id,
      args: args,
      conf: Oban.config(@oban),
      attempt: 1,
      max_attempts: 26
    })
  rescue
    error -> {:raised, error.__struct__}
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
