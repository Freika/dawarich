defmodule Dawarich.Release.CloudReadinessTest.Pending do
  def release, do: "l1-required-data-proof"
  def steps, do: []
  def data_versions, do: ["20991007000002"]
end

defmodule Dawarich.Release.CloudReadinessTest do
  use Dawarich.ScratchCase, async: false
  alias Dawarich.{Release, ReleaseMigrator, ReleaseMigrations}
  alias Dawarich.Release.Cloud

  setup do
    scratch_sql!(ReleaseMigrator.baseline_sql())

    ScratchRepo.query!("DELETE FROM ar_internal_metadata WHERE key='phoenix_native_baseline'", [],
      log: false
    )

    Release.install_schemas(ScratchRepo)

    versions =
      (ReleaseMigrations.all() ++ [__MODULE__.Pending])
      |> Enum.flat_map(& &1.data_versions())
      |> Kernel.++(Dawarich.RailsTree.versions("data"))
      |> Enum.uniq()

    ScratchRepo.query!(
      "INSERT INTO data_migrations(version) SELECT unnest($1::text[]) ON CONFLICT DO NOTHING",
      [versions],
      log: false
    )

    ScratchRepo.query!("DELETE FROM phoenix.release_operations", [], log: false)
    ScratchRepo.query!("DELETE FROM phoenix.processed_commands", [], log: false)
    ScratchRepo.query!("DELETE FROM phoenix.release_migration_jobs", [], log: false)
    ScratchRepo.query!("DELETE FROM oban.oban_jobs", [], log: false)
    assert :ok = Cloud.migrate(ScratchRepo, opts())
    old_repo = Application.fetch_env!(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)
    on_exit(fn -> Application.put_env(:dawarich, :jobs_repo, old_repo) end)

    start_supervised!(
      {Oban, name: __MODULE__.Oban, repo: ScratchRepo, prefix: "oban", testing: :manual}
    )

    :ok
  end

  test "L1 Cloud readiness observes all ledgers and pending operations without mutation" do
    assert Cloud.ready?(ScratchRepo, opts())
    reader = "l1_cloud_reader_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    ScratchRepo.query!("CREATE ROLE #{reader} LOGIN PASSWORD 'synthetic-l1-reader'", [],
      log: false
    )

    for schema <- ~w(public phoenix oban) do
      ScratchRepo.query!("GRANT USAGE ON SCHEMA #{schema} TO #{reader}", [], log: false)

      ScratchRepo.query!("GRANT SELECT ON ALL TABLES IN SCHEMA #{schema} TO #{reader}", [],
        log: false
      )
    end

    on_exit(fn ->
      ScratchRepo.query!("DROP OWNED BY #{reader} CASCADE", [], log: false)
      ScratchRepo.query!("DROP ROLE #{reader}", [], log: false)
    end)

    pool =
      start_supervised!(
        {ScratchRepo, name: nil, pool_size: 2, username: reader, password: "synthetic-l1-reader"},
        id: :cloud_reader_pool
      )

    previous = ScratchRepo.get_dynamic_repo()
    ScratchRepo.put_dynamic_repo(pool)

    try do
      assert ScratchRepo.query!(
               "SELECT has_schema_privilege(current_user,'phoenix','CREATE')",
               [],
               log: false
             ).rows == [[false]]

      assert read_only_ready?()
    after
      ScratchRepo.put_dynamic_repo(previous)
    end

    for table <-
          ~w(public.schema_migrations public.data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations) do
      [[version]] =
        ScratchRepo.query!("SELECT version FROM #{table} ORDER BY version LIMIT 1", [],
          log: false
        ).rows

      ScratchRepo.query!("DELETE FROM #{table} WHERE version=$1", [version], log: false)
      before = snapshot()
      refute read_only_ready?()
      assert snapshot() == before
      ScratchRepo.query!("INSERT INTO #{table}(version) VALUES($1)", [version], log: false)
    end

    event = Ecto.UUID.generate()

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_operations(id,command_type,cursor) VALUES($1,'release.family_backfill','{}')",
      [Ecto.UUID.dump!(event)],
      log: false
    )

    before = snapshot()
    refute read_only_ready?()
    assert snapshot() == before

    ScratchRepo.query!(
      "UPDATE phoenix.release_operations SET status='completed',completed_at=now()",
      [],
      log: false
    )

    assert Cloud.ready?(ScratchRepo, opts())

    ScratchRepo.query!(
      "INSERT INTO phoenix.release_migration_jobs(version,job_class,arguments,wait_seconds) VALUES('20991007000001','DataMigrations::FixRouteOpacityJob','[]',0)",
      [],
      log: false
    )

    before = snapshot()
    refute read_only_ready?()
    assert snapshot() == before
    assert {:error, :pending_release_jobs} = Cloud.migrate(ScratchRepo, opts())
    assert {:error, :pending_release_jobs} = Cloud.migrate(ScratchRepo, opts())
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs", [], log: false).rows == [[1]]
    refute Cloud.ready?(ScratchRepo, opts())
    [[id, args]] = ScratchRepo.query!("SELECT id,args FROM oban.oban_jobs", [], log: false).rows

    ScratchRepo.query!(
      "INSERT INTO users(email,encrypted_password,settings,created_at,updated_at) VALUES('cloud-route@example.test','','{\"route_opacity\":50}',now(),now())",
      [],
      log: false
    )

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__.Oban, queue: :maintenance, with_scheduled: true)

    assert ScratchRepo.query!("SELECT settings->'route_opacity' FROM users", [], log: false).rows ==
             [[0.5]]

    assert ScratchRepo.query!("SELECT state FROM oban.oban_jobs WHERE id=$1", [id], log: false).rows ==
             [["completed"]]

    assert is_binary(args["event_id"])
    assert Cloud.ready?(ScratchRepo, opts())
    assert :ok = Cloud.migrate(ScratchRepo, opts())
    ScratchRepo.query!("DELETE FROM oban.oban_jobs", [], log: false)
    assert Cloud.ready?(ScratchRepo, opts())
    assert :ok = Cloud.migrate(ScratchRepo, opts())
    assert ScratchRepo.query!("SELECT count(*) FROM oban.oban_jobs", [], log: false).rows == [[0]]

    parent = self()

    holder =
      Task.async(fn ->
        ScratchRepo.transaction(fn ->
          ScratchRepo.query!(
            "LOCK TABLE phoenix.phoenix_schema_migrations IN SHARE UPDATE EXCLUSIVE MODE",
            [],
            log: false
          )

          send(parent, {:locked, self()})

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive {:locked, pid}, 2000
    ready = Task.async(fn -> Cloud.ready?(ScratchRepo, opts()) end)
    result = Task.yield(ready, 1000)
    send(pid, :release)
    Task.await(holder)
    assert result == {:ok, true}

    ScratchRepo.query!(
      "ALTER TABLE phoenix.phoenix_schema_migrations RENAME TO cloud_missing_ledger",
      [],
      log: false
    )

    before = catalog()
    refute Cloud.ready?(ScratchRepo, opts())
    assert catalog() == before

    ScratchRepo.query!(
      "ALTER TABLE phoenix.cloud_missing_ledger RENAME TO phoenix_schema_migrations",
      [],
      log: false
    )
  end

  defp opts,
    do: [
      env: %{
        "SELF_HOSTED" => "false",
        "MANAGER_URL" => "https://manager.example.invalid",
        "JWT_SECRET_KEY" => "synthetic-l1-config"
      },
      releases: ReleaseMigrations.all() ++ [__MODULE__.Pending],
      command: fn _ -> {:ok, nil} end
    ]

  defp read_only_ready? do
    parent = self()
    ref = make_ref()
    id = {__MODULE__, ref}

    :telemetry.attach(
      id,
      [:dawarich, :scratch_case_repo, :query],
      fn _, _, meta, _ -> if self() == parent, do: send(parent, {ref, meta.query}) end,
      nil
    )

    try do
      result = Cloud.ready?(ScratchRepo, opts())
      queries = queries(ref, [])
      assert queries != []
      assert Enum.all?(queries, &String.starts_with?(String.trim_leading(&1), "SELECT"))
      result
    after
      :telemetry.detach(id)
    end
  end

  defp queries(ref, acc) do
    receive do
      {^ref, query} -> queries(ref, [query | acc])
    after
      0 -> acc
    end
  end

  defp snapshot,
    do:
      for(
        table <-
          ~w(schema_migrations data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations phoenix.release_operations phoenix.release_migration_jobs phoenix.processed_commands phoenix.registration_setting oban.oban_jobs),
        do:
          ScratchRepo.query!(
            "SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text",
            [],
            log: false
          ).rows
      )

  defp catalog,
    do:
      ScratchRepo.query!(
        "SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','phoenix','oban') ORDER BY 1,2",
        [],
        log: false
      ).rows
end
