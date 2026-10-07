defmodule Dawarich.ReleaseJobs.CloudFamilyBackfillTest do
  use Dawarich.JobsCase

  alias Dawarich.{ReleaseJobs, ReleaseOperations, Wave6Fixtures}
  alias Dawarich.ReleaseJobs.FamilyBackfill
  alias Dawarich.Jobs.{Dispatch, Ownership}
  alias Dawarich.Release.CloudJobs

  @oban __MODULE__.Oban
  @classes [
    {"DataMigrations::BackfillFamiliesForFamilyPlanJob", "families"},
    {"DataMigrations::BackfillFamilyMemberEntitlementsJob", "entitlements"}
  ]

  setup do
    old = Map.new(~w(SELF_HOSTED TIME_ZONE), &{&1, System.get_env(&1)})
    System.put_env("SELF_HOSTED", "false")
    System.put_env("TIME_ZONE", "Europe/Berlin")

    on_exit(fn ->
      for {key, value} <- old do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    start_oban(@oban)
    rows("DELETE FROM phoenix.release_migration_jobs")
    Ownership.put!(ScratchRepo, "command:mail.family_lapse", :oban)
    :ok
  end

  test "L1 both Cloud family classes decode dispatch and retain operation identity" do
    for {class, phase} <- @classes do
      assert {:ok, FamilyBackfill, decoded} = ReleaseJobs.decode(class, [])

      assert decoded["cursor"] == %{
               "phase" => phase,
               "after_id" => 0,
               "time_zone" => "Europe/Berlin"
             }

      assert {:ok, _} = Ecto.UUID.cast(decoded["operation_id"])
      assert ReleaseJobs.decode(class, [1]) == {:error, :invalid_arguments}
      assert {:ok, FamilyBackfill} = Dawarich.Jobs.Registry.command("release.family_backfill")
      event = outbox!(command_type: "release.family_backfill", payload: decoded["cursor"])
      assert %{dispatched: 1} = Dispatch.run(repo: ScratchRepo, oban: @oban)
      [[args]] = rows("SELECT args FROM oban.oban_jobs WHERE args->>'event_id'=$1", [event])
      assert run(args) == :ok
      assert run(args) == :ok

      assert rows("SELECT status FROM phoenix.release_operations WHERE id=$1", [
               Ecto.UUID.dump!(event)
             ]) == [["completed"]]

      assert FamilyBackfill.args_from_command(2, decoded["cursor"]) ==
               {:error, "unsupported_version"}

      assert FamilyBackfill.args_from_command(1, Map.put(decoded["cursor"], "extra", 1)) ==
               {:error, "invalid_payload"}

      System.put_env("SELF_HOSTED", "true")
      assert ReleaseJobs.decode(class, []) == :skip
      System.put_env("SELF_HOSTED", "false")
    end

    System.put_env("TIME_ZONE", "invalid-zone")

    for {class, _} <- @classes do
      assert ReleaseJobs.decode(class, []) == {:error, :invalid_arguments}
    end
  end

  test "L1 family-plan backfill crosses the 500 boundary without duplicate families" do
    assert {:ok, FamilyBackfill, args} = ReleaseJobs.decode(elem(hd(@classes), 0), [])
    invalid = put_in(args, ["cursor", "after_id"], -1)
    assert admit(invalid) == {:cancel, :invalid_payload}
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    eligible = for _ <- 1..501, do: user!(2)
    deleted = user!(2)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [deleted])
    creator = user!(2)
    family = family!(creator)
    member = user!(2)
    membership!(family, member)
    user!(0)
    user!(1)
    inactive = user!(2, ~N[2020-01-01 00:00:00])
    expected = eligible ++ [inactive]
    assert {:ok, FamilyBackfill, args} = ReleaseJobs.decode(elem(hd(@classes), 0), [])

    assert run(args) == :ok
    assert length(children()) == 500
    assert Enum.map(children(), & &1["user_id"]) == Enum.take(expected, 500)
    assert :ok = stop_supervised(@oban)
    start_oban(@oban)
    assert run(args) == :ok
    assert length(children()) == 500

    [[next]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
        Oban.Worker.to_string(FamilyBackfill)
      ])

    assert next["operation_id"] == args["operation_id"]
    assert next["cursor"]["time_zone"] == "Europe/Berlin"
    assert run(next) == :ok
    assert Enum.map(children(), & &1["user_id"]) == expected

    for child <- children() do
      assert Dawarich.Families.AutoCreateWorker.perform(%Oban.Job{args: child}) == :ok
      assert Dawarich.Families.AutoCreateWorker.perform(%Oban.Job{args: child}) == :ok
    end

    assert run(next) == :ok
    assert rows("SELECT count(*) FROM families") == [[503]]
    assert rows("SELECT count(*) FROM family_memberships") == [[503]]
    assert rows("SELECT count(DISTINCT creator_id) FROM families") == [[503]]
    assert rows("SELECT count(*) FROM notifications") == [[502]]
    assert rows("SELECT count(*) FROM families WHERE creator_id=$1", [deleted]) == [[0]]
    assert rows("SELECT count(*) FROM families WHERE creator_id=$1", [member]) == [[0]]
    assert rows("SELECT count(*) FROM families WHERE access_until='2020-01-01'") == [[1]]
  end

  test "L1 entitlement backfill crosses the 200 boundary without notifications or subscription loss" do
    assert {:ok, FamilyBackfill, args} = ReleaseJobs.decode(elem(List.last(@classes), 0), [])
    invalid = put_in(args, ["cursor", "time_zone"], "invalid-zone")
    assert admit(invalid) == {:cancel, :invalid_payload}

    cases =
      for n <- 1..201 do
        expiry =
          if rem(n, 2) == 0,
            do: ~N[2099-10-25 01:30:00.000000],
            else: ~N[2020-10-25 01:30:00.000000]

        owner = user!(2, expiry)
        family = family!(owner)
        member = user!(0, nil)
        paid = user!(2, ~N[2099-12-01 00:00:00])
        rows("UPDATE users SET status=1,subscription_source=1 WHERE id=$1", [paid])
        membership!(family, member)
        membership!(family, paid)
        {family, member, paid, expiry}
      end

    assert {:ok, FamilyBackfill, args} = ReleaseJobs.decode(elem(List.last(@classes), 0), [])
    assert run(args) == :ok
    assert rows("SELECT count(*) FROM families WHERE access_until IS NOT NULL") == [[200]]
    [[next]] = rows("SELECT args FROM oban.oban_jobs")
    assert next["operation_id"] == args["operation_id"]
    assert run(next) == :ok
    assert run(args) == :ok
    assert run(next) == :ok
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    for {family, member, paid, expiry} <- cases do
      assert rows("SELECT access_until FROM families WHERE id=$1", [family]) == [[expiry]]
      {plan, status, marked} = if expiry.year == 2099, do: {1, 1, false}, else: {0, 0, true}

      assert rows(
               "SELECT plan,status,active_until,settings->'family'->>'plan_lapse_notified_at' IS NOT NULL FROM users WHERE id=$1",
               [member]
             ) == [[plan, status, expiry, marked]]

      assert rows("SELECT plan,status,active_until,subscription_source FROM users WHERE id=$1", [
               paid
             ]) == [[2, 1, ~N[2099-12-01 00:00:00.000000], 1]]
    end
  end

  test "L1 family operation failure never records unfinished data as ready" do
    user!(2)
    assert {:ok, FamilyBackfill, args} = ReleaseJobs.decode(elem(hd(@classes), 0), [])
    invalid = Map.put(args, "operation_id", "invalid-id")
    assert admit(invalid) == {:cancel, :invalid_payload}

    rows(
      "ALTER TABLE oban.oban_jobs ADD CONSTRAINT l1_family_child_failure CHECK(worker <> 'Dawarich.Families.AutoCreateWorker')"
    )

    try do
      assert_raise Ecto.ConstraintError, fn -> run(args) end

      assert rows("SELECT cursor,status FROM phoenix.release_operations") == [
               [args["cursor"], "running"]
             ]

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      refute CloudJobs.ready?(ScratchRepo)
    after
      rows("ALTER TABLE oban.oban_jobs DROP CONSTRAINT l1_family_child_failure")
    end

    assert {:ok, _} = ReleaseOperations.resume(ScratchRepo, @oban, args["operation_id"])

    assert ReleaseOperations.resume(ScratchRepo, @oban, args["operation_id"]) ==
             {:error, :not_resumable}

    assert %{success: 2, failure: 0} =
             Oban.drain_queue(@oban,
               queue: :maintenance,
               with_recursion: true,
               with_scheduled: true
             )

    assert rows("SELECT count(*) FROM families") == [[1]]
    assert CloudJobs.ready?(ScratchRepo)
    assert run(args) == :ok
    assert rows("SELECT count(*) FROM families") == [[1]]

    reset!(ScratchRepo)
    user!(2)
    versions = rows("SELECT version FROM data_migrations ORDER BY version")

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.ReleaseMigrator.Jobs.insert!(
                 ScratchRepo,
                 "20260908115001",
                 {elem(hd(@classes), 0), [], 120},
                 :record
               )
             end)

    reconcile = fn ->
      Dawarich.ReleaseMigrator.Lease.with_lease(ScratchRepo, [], fn lease ->
        CloudJobs.reconcile(ScratchRepo, lease)
      end)
    end

    assert :ok = reconcile.()
    original = rows("SELECT args,scheduled_at FROM oban.oban_jobs")
    assert :ok = reconcile.()
    assert rows("SELECT args,scheduled_at FROM oban.oban_jobs") == original

    assert rows(
             "SELECT extract(epoch FROM j.scheduled_at-r.recorded_at)::integer FROM oban.oban_jobs j JOIN phoenix.release_migration_jobs r ON j.meta->>'cloud_release_record'=r.id::text"
           ) == [[120]]

    refute CloudJobs.ready?(ScratchRepo)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(@oban, queue: :maintenance, with_scheduled: true, with_limit: 1)

    assert rows("SELECT status FROM phoenix.release_operations") == [["completed"]]
    assert rows("SELECT count(*) FROM families") == [[0]]
    refute CloudJobs.ready?(ScratchRepo)
    assert rows("SELECT version FROM data_migrations ORDER BY version") == versions

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(@oban, queue: :maintenance, with_scheduled: true)

    assert CloudJobs.ready?(ScratchRepo)
    assert :ok = reconcile.()
    assert rows("SELECT version FROM data_migrations ORDER BY version") == versions
    assert rows("SELECT count(*) FROM families") == [[1]]
  end

  defp admit(args) do
    FamilyBackfill.perform(%Oban.Job{args: args})
  rescue
    error -> {:raised, error.__struct__}
  end

  defp run(args),
    do: FamilyBackfill.perform(%Oban.Job{args: args, conf: Oban.config(@oban)})

  defp children,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Families.AutoCreateWorker' ORDER BY id"
      )
      |> List.flatten()

  defp user!(plan, expiry \\ ~N[2099-12-01 00:00:00]),
    do: Wave6Fixtures.user!(%{"plan" => plan, "active_until" => expiry})

  defp family!(owner),
    do:
      Wave6Fixtures.insert!("families", %{
        "creator_id" => owner,
        "name" => "Synthetic family",
        "created_at" => ~N[2020-01-01 00:00:00],
        "updated_at" => ~N[2020-01-01 00:00:00]
      })

  defp membership!(family, member),
    do:
      rows(
        "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,1,now(),now())",
        [family, member]
      )
end
