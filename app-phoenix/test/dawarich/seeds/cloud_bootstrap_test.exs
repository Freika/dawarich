defmodule Dawarich.Seeds.CloudBootstrapTest do
  use Dawarich.JobsCase
  import Dawarich.AnomalyCase
  alias Dawarich.Seeds.BootstrapUser
  alias Dawarich.Users.CreationEffects
  alias Dawarich.Jobs.Ownership
  alias Dawarich.ReleaseMigrator.Lease
  @env %{"SELF_HOSTED" => "false", "TIME_ZONE" => "Europe/Berlin"}
  @now ~N[2026-10-07 12:00:00.000000]

  test "L1 Cloud bootstrap omits demo admin while ordinary creation retains Rails trial effects" do
    assert BootstrapUser.run(ScratchRepo, env: @env, now: @now) == :ok
    assert rows("SELECT count(*) FROM users") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    id = user!()

    for type <- ~w(mail.user.welcome users.explore_features_mail users.creation_webhook),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               CreationEffects.apply(ScratchRepo, id, env: @env, now: @now)
             end)

    assert rows("SELECT admin,status,active_until,length(api_key) FROM users WHERE id=$1", [id]) ==
             [[false, 2, ~N[2026-10-14 12:00:00.000000], 64]]

    assert rows("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [id]) == [[3]]
  end

  test "L1 populated Cloud seed and release reentry never recreate user or callback identities" do
    id = user!()

    rows(
      "UPDATE users SET status=1,plan=2,active_until='2027-01-01',api_key='synthetic-existing-key' WHERE id=$1",
      [id]
    )

    for type <- ~w(mail.user.welcome users.explore_features_mail users.creation_webhook),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    opts = fixture_options()
    before = snapshot()

    for _ <- 1..2 do
      assert Lease.with_lease(ScratchRepo, opts, fn lease ->
               Dawarich.Seeds.run(ScratchRepo, Keyword.put(opts, :lease, lease))
             end) == :ok

      assert snapshot() == before
    end

    rows("UPDATE users SET deleted_at=$2 WHERE id=$1", [id, @now])

    assert Lease.with_lease(ScratchRepo, opts, fn lease ->
             Dawarich.Seeds.run(ScratchRepo, Keyword.put(opts, :lease, lease))
           end) == :ok

    assert snapshot() == before
    assert rows("SELECT count(*) FROM users") == [[1]]
    assert rows("SELECT count(*) FROM tags WHERE user_id=$1", [id]) == [[4]]
    assert rows("SELECT count(*) FROM phoenix.release_migrator_leases") == [[0]]
  end

  test "R2 Cloud demo admin omission has an authorized ED row handoff to F" do
    doc = File.read!(Path.expand("../../../../docs/phoenix/l1-b-cloud-registration.md", __DIR__))
    row = Enum.find(String.split(doc, "\n"), &String.starts_with?(&1, "| F assigns ED ID |"))
    assert is_binary(row)
    assert row =~ "Ordinary Cloud demo administrator bootstrap"
    assert row =~ "Eugene ruling 2026-10-07"
    assert row =~ "seeds/cloud_bootstrap_test.exs"
    assert row =~ "closed (approved difference; public Cloud lifecycle remains refused)"
    assert BootstrapUser.run(ScratchRepo, env: @env, now: @now) == :ok
    assert rows("SELECT count(*) FROM users") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
  end

  defp snapshot do
    rows(
      "SELECT id,status,plan,active_until,length(api_key),api_key='synthetic-existing-key' FROM users ORDER BY id"
    ) ++
      rows("SELECT event_id,command_type FROM job_outbox ORDER BY event_id") ++
      rows("SELECT event_id,handler FROM phoenix.processed_commands ORDER BY event_id")
  end

  defp fixture_options do
    c = Dawarich.A12hSeeds.case!("A12h_fresh")
    priv = Dawarich.A12hSeeds.country_priv!(c["sources"]["countries"])
    asset = Path.join(priv, "regions.json")
    File.write!(asset, Jason.encode!(c["sources"]["regions"]))
    [env: @env, now: @now, priv_dir: priv, asset: asset]
  end
end
