defmodule Dawarich.Seeds.CloudBootstrapTest do
  use Dawarich.JobsCase
  import Dawarich.AnomalyCase
  alias Dawarich.Seeds.BootstrapUser
  alias Dawarich.Users.CreationEffects
  alias Dawarich.Jobs.Ownership
  alias Dawarich.ReleaseMigrator.Lease

  @env %{
    "SELF_HOSTED" => "false",
    "TIME_ZONE" => "Europe/Berlin",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-l1-config"
  }
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

  test "R4 Cloud creation and seed reentry preserve source and private migration ledgers" do
    rows("DELETE FROM phoenix.release_migration_jobs")
    rows("DELETE FROM phoenix.release_migrator_leases")
    rows("DELETE FROM public.data_migrations")
    rows("DELETE FROM public.ar_internal_metadata WHERE key='phoenix_native_baseline'")

    rows("INSERT INTO public.data_migrations(version) SELECT unnest($1::text[])", [
      Dawarich.RailsTree.versions("data")
    ])

    opts = [env: @env, command: fn _ -> {:ok, nil} end]
    assert :ok = Dawarich.Release.Cloud.migrate(ScratchRepo, opts)
    assert Dawarich.Release.Cloud.ready?(ScratchRepo, opts)
    id = user!()

    for type <- ~w(mail.user.welcome users.explore_features_mail users.creation_webhook),
        do: Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    for table <-
          ~w(public.data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations) do
      [[removed]] =
        rows(
          "DELETE FROM #{table} WHERE version=(SELECT max(version) FROM #{table}) RETURNING row_to_json(#{List.last(String.split(table, "."))})"
        )

      try do
        refute Dawarich.Release.Cloud.ready?(ScratchRepo, opts)
        before = migration_ledgers()

        assert {:ok, :ok} =
                 ScratchRepo.transaction(fn ->
                   CreationEffects.apply(ScratchRepo, id, env: @env, now: @now)
                 end)

        seed_opts = fixture_options()

        assert :ok =
                 Lease.with_lease(ScratchRepo, seed_opts, fn lease ->
                   Dawarich.Seeds.run(ScratchRepo, Keyword.put(seed_opts, :lease, lease))
                 end)

        assert migration_ledgers() == before
        refute Dawarich.Release.Cloud.ready?(ScratchRepo, opts)
      after
        rows("INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1)", [
          removed
        ])
      end

      assert Dawarich.Release.Cloud.ready?(ScratchRepo, opts)
    end
  end

  defp migration_ledgers do
    for table <-
          ~w(public.schema_migrations public.data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations public.ar_internal_metadata) do
      {table, rows("SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text")}
    end
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
