defmodule Dawarich.Release.CloudProvisioningTest.Probe do
  import Dawarich.ReleaseMigration
  def release, do: "l1-cloud-probe"
  def data_versions, do: []

  def steps do
    [
      {"20991007000001",
       fn repo ->
         sql!(repo, "INSERT INTO cloud_probe VALUES (1)")
         if gate = Process.get(:cloud_step_gate), do: gate.()
         :ok
       end}
    ]
  end
end

defmodule Dawarich.Release.CloudProvisioningTest do
  use Dawarich.ScratchCase, async: false
  alias Dawarich.Release
  alias Dawarich.Release.{Cloud, CloudPreflight}
  alias __MODULE__.Probe

  setup do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")

    for schema <- ~w(phoenix oban),
        do: ScratchRepo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE", [], log: false)

    Dawarich.MigrationModules.purge()

    for extension <- ~w(pgcrypto postgis),
        do: ScratchRepo.query!("CREATE EXTENSION IF NOT EXISTS #{extension}", [], log: false)

    for schema <- ~w(phoenix oban),
        do: ScratchRepo.query!("CREATE SCHEMA #{schema}", [], log: false)

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")

      Dawarich.ScratchCase.recreate_public!(ScratchRepo)
      Dawarich.MigrationModules.purge()
      Release.install_schemas(ScratchRepo)
    end)

    :ok
  end

  test "L1 Cloud component provisions fresh precreated schemas without database CREATE" do
    role = "l1_cloud_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    ScratchRepo.query!("CREATE ROLE #{role} LOGIN PASSWORD 'synthetic-l1-role'", [], log: false)

    for schema <- ~w(public phoenix oban),
        do: ScratchRepo.query!("ALTER SCHEMA #{schema} OWNER TO #{role}", [], log: false)

    pool =
      start_supervised!(
        {ScratchRepo, name: nil, pool_size: 3, username: role, password: "synthetic-l1-role"},
        id: :cloud_role_pool
      )

    on_exit(fn ->
      ScratchRepo.query!("DROP OWNED BY #{role} CASCADE", [], log: false)
      ScratchRepo.query!("DROP ROLE #{role}", [], log: false)

      for schema <- ~w(public phoenix oban),
          do: ScratchRepo.query!("CREATE SCHEMA IF NOT EXISTS #{schema}", [], log: false)
    end)

    previous = ScratchRepo.get_dynamic_repo()
    ScratchRepo.put_dynamic_repo(pool)

    try do
      assert ScratchRepo.query!(
               "SELECT has_database_privilege(current_user,current_database(),'CREATE')",
               [],
               log: false
             ).rows == [[false]]

      assert :ok = Cloud.migrate(ScratchRepo, opts())

      for table <-
            ~w(users schema_migrations data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations),
          do: assert(relation?(table))

      before = snapshot()
      assert :ok = Cloud.migrate(ScratchRepo, opts())
      assert snapshot() == before
      assert Cloud.ready?(ScratchRepo, opts())
    after
      ScratchRepo.put_dynamic_repo(previous)
    end
  end

  test "L1 Cloud component refuses missing schemas wrong owners and unsupported ledgers before writes" do
    for schema <- ~w(public phoenix oban) do
      ScratchRepo.query!("DROP SCHEMA #{schema} CASCADE", [], log: false)
      before = catalog()
      assert {:error, _} = Cloud.migrate(ScratchRepo, opts())
      assert catalog() == before
      ScratchRepo.query!("CREATE SCHEMA #{schema}", [], log: false)

      if schema == "public" do
        for extension <- ~w(pgcrypto postgis),
            do: ScratchRepo.query!("CREATE EXTENSION IF NOT EXISTS #{extension}", [], log: false)
      end
    end

    for extension <- ~w(pgcrypto postgis),
        do: ScratchRepo.query!("CREATE EXTENSION IF NOT EXISTS #{extension}", [], log: false)

    assert {:error, :registration_copy_refused} =
             Cloud.migrate(ScratchRepo, opts(command: fn _ -> {:error, :unavailable} end))

    refute relation?("schema_migrations")

    assert {:error, :registration_copy_refused} =
             Cloud.migrate(ScratchRepo, opts(command: fn _ -> {:ok, "unreadable"} end))

    refute relation?("phoenix.registration_setting")

    ScratchRepo.query!("CREATE TABLE schema_migrations(version varchar PRIMARY KEY)", [],
      log: false
    )

    for versions <- [
          ["99999999999999"],
          Enum.take(Dawarich.ReleaseMigrator.Floor.versions(), 1),
          Dawarich.ReleaseMigrator.Floor.versions() ++ ["99999999999999"]
        ] do
      ScratchRepo.query!("TRUNCATE schema_migrations", [], log: false)

      ScratchRepo.query!("INSERT INTO schema_migrations SELECT unnest($1::text[])", [versions],
        log: false
      )

      before = catalog()
      assert {:error, _} = Cloud.migrate(ScratchRepo, opts())
      assert catalog() == before
    end

    ScratchRepo.query!("DROP TABLE schema_migrations", [], log: false)

    ScratchRepo.query!(
      "CREATE TABLE phoenix.phoenix_schema_migrations(version bigint PRIMARY KEY)",
      [],
      log: false
    )

    ScratchRepo.query!("INSERT INTO phoenix.phoenix_schema_migrations VALUES(29990101000000)", [],
      log: false
    )

    before = catalog()
    assert {:error, :newer_private_schema} = Cloud.migrate(ScratchRepo, opts())
    assert catalog() == before
    ScratchRepo.query!("DROP TABLE phoenix.phoenix_schema_migrations", [], log: false)
    role = "l1_wrong_owner_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    ScratchRepo.query!("CREATE ROLE #{role} LOGIN PASSWORD 'synthetic-l1-role'", [], log: false)

    on_exit(fn ->
      ScratchRepo.query!("DROP OWNED BY #{role} CASCADE", [], log: false)
      ScratchRepo.query!("DROP ROLE #{role}", [], log: false)
    end)

    for schema <- ~w(public phoenix oban),
        do: ScratchRepo.query!("GRANT USAGE ON SCHEMA #{schema} TO #{role}", [], log: false)

    ScratchRepo.query!("GRANT CREATE ON SCHEMA phoenix TO #{role}", [], log: false)

    pool =
      start_supervised!(
        {ScratchRepo, name: nil, pool_size: 2, username: role, password: "synthetic-l1-role"},
        id: :wrong_owner_pool
      )

    previous = ScratchRepo.get_dynamic_repo()
    ScratchRepo.put_dynamic_repo(pool)

    try do
      before = catalog()
      assert {:error, :schema_permissions} = CloudPreflight.check(ScratchRepo, opts())
      assert {:error, :schema_permissions} = Cloud.migrate(ScratchRepo, opts())
      assert catalog() == before
    after
      ScratchRepo.put_dynamic_repo(previous)
    end

    for schema <- ~w(public phoenix oban),
        do: ScratchRepo.query!("GRANT CREATE ON SCHEMA #{schema} TO #{role}", [], log: false)

    ScratchRepo.query!("CREATE TABLE cloud_foreign(id int)", [], log: false)
    ScratchRepo.put_dynamic_repo(pool)

    try do
      assert {:error, :table_ownership} = CloudPreflight.check(ScratchRepo, opts())
    after
      ScratchRepo.put_dynamic_repo(previous)
    end
  end

  test "L1 Cloud component upgrades populated source data under the existing lease and Rails exclusion" do
    source_fixture!()

    before =
      rows_snapshot(
        ~w(users families family_memberships service_settings active_storage_blobs active_storage_attachments)
      )

    assert :ok = Cloud.migrate(ScratchRepo, opts())

    assert rows_snapshot(
             ~w(users families family_memberships service_settings active_storage_blobs active_storage_attachments)
           ) == before

    assert :ok = Cloud.migrate(ScratchRepo, opts())
    ScratchRepo.query!("CREATE TABLE cloud_probe(id int)", [], log: false)
    opts = opts(releases: Dawarich.ReleaseMigrations.all() ++ [Probe], lease_wait_ms: 0)
    parent = self()

    holder =
      Task.async(fn ->
        Dawarich.Release.Native.with_lock(ScratchRepo, opts, fn ->
          send(parent, {:locked, self()})

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive {:locked, pid}, 2000
    assert {:error, :migration_lock_busy} = Cloud.migrate(ScratchRepo, opts)
    assert ScratchRepo.query!("SELECT count(*) FROM cloud_probe", [], log: false).rows == [[0]]
    send(pid, :release)
    Task.await(holder)

    Process.put(:cloud_step_gate, fn ->
      ScratchRepo.query!("DELETE FROM phoenix.release_migrator_leases", [], log: false)
    end)

    assert {:error, _} = Cloud.migrate(ScratchRepo, opts)
    assert ScratchRepo.query!("SELECT count(*) FROM cloud_probe", [], log: false).rows == [[0]]

    assert ScratchRepo.query!(
             "SELECT count(*) FROM schema_migrations WHERE version='20991007000001'",
             [],
             log: false
           ).rows == [[0]]

    Process.delete(:cloud_step_gate)
    ScratchRepo.query!("DELETE FROM phoenix.registration_setting", [], log: false)

    lose = fn :before_registration_copy, _ ->
      ScratchRepo.query!("DELETE FROM phoenix.release_migrator_leases", [], log: false)
      :ok
    end

    assert {:error, :lease_lost} = Cloud.migrate(ScratchRepo, opts(hook: lose))

    assert ScratchRepo.query!("SELECT count(*) FROM phoenix.registration_setting", [], log: false).rows ==
             [[0]]

    ref = make_ref()
    telemetry = {__MODULE__, ref}

    :telemetry.attach(
      telemetry,
      [:dawarich, :scratch_case_repo, :query],
      fn _, _, meta, _ ->
        if self() == parent and Process.get(ref) != true and
             String.starts_with?(meta.query, "INSERT INTO phoenix.registration_setting") do
          Process.put(ref, true)
          ScratchRepo.query!("DELETE FROM phoenix.release_migrator_leases", [], log: false)
        end
      end,
      nil
    )

    try do
      assert {:error, :lease_lost} = Cloud.migrate(ScratchRepo, opts())

      assert ScratchRepo.query!("SELECT count(*) FROM phoenix.registration_setting", [],
               log: false
             ).rows ==
               [[0]]
    after
      :telemetry.detach(telemetry)
      Process.delete(ref)
    end
  end

  test "L1 Cloud component preserves copied false and nil registration authority on reentry" do
    fixture =
      Dawarich.RailsTree.read("app-phoenix/test/fixtures/auth/activation.json") |> Jason.decode!()

    for value <- ["false", "nil"] do
      for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

      {:ok, previous} = Dawarich.Redis.cache_command(["GET", "dawarich/registration_enabled"])

      try do
        {:ok, _} =
          Dawarich.Redis.cache_command([
            "SET",
            "dawarich/registration_enabled",
            Base.decode64!(fixture["registration"][value])
          ])

        assert :ok =
                 Cloud.migrate(ScratchRepo, Keyword.delete(opts(), :command))

        expected = if value == "false", do: false, else: nil

        assert ScratchRepo.query!("SELECT enabled FROM phoenix.registration_setting", [],
                 log: false
               ).rows == [[expected]]

        assert :ok =
                 Cloud.migrate(
                   ScratchRepo,
                   opts(command: fn _ -> flunk("PG is authoritative") end)
                 )

        assert ScratchRepo.query!("SELECT enabled FROM phoenix.registration_setting", [],
                 log: false
               ).rows == [[expected]]

        ScratchRepo.query!("DELETE FROM phoenix.registration_setting", [], log: false)
      after
        if previous do
          Dawarich.Redis.cache_command(["SET", "dawarich/registration_enabled", previous])
        else
          Dawarich.Redis.cache_command(["DEL", "dawarich/registration_enabled"])
        end
      end

      for spec <- Dawarich.Redis.cache_child_specs(), do: stop_supervised(spec.id)
    end
  end

  defp opts(extra \\ []),
    do:
      Keyword.merge(
        [
          env: %{"SELF_HOSTED" => "false", "ALLOW_EMAIL_PASSWORD_REGISTRATION" => "true"},
          command: fn _ -> {:ok, nil} end
        ],
        extra
      )

  defp relation?(table),
    do:
      ScratchRepo.query!("SELECT to_regclass($1) IS NOT NULL", [table], log: false).rows == [
        [true]
      ]

  defp catalog,
    do:
      ScratchRepo.query!(
        "SELECT n.nspname,c.relname,c.relowner FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','phoenix','oban') ORDER BY 1,2",
        [],
        log: false
      ).rows

  defp snapshot,
    do:
      rows_snapshot(
        ~w(schema_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations phoenix.registration_setting oban.oban_jobs)
      )

  defp rows_snapshot(tables) do
    for table <- tables do
      rows =
        ScratchRepo.query!(
          "SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text",
          [],
          log: false
        ).rows

      {table, length(rows), Base.encode16(:crypto.hash(:sha256, Jason.encode!(rows)))}
    end
  end

  defp source_fixture! do
    root = Path.join(System.tmp_dir!(), "cloud-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    schema =
      Dawarich.RailsTree.read("db/schema.rb")
      |> String.replace(~r/^  create_table "job_outbox".*?^  end\n\n/ms, "")
      |> String.replace(
        ~r/^    t\.(?:datetime "map_matched_at"|jsonb "map_matching_data"|string "map_matching_input_digest"|integer "map_matching_status"|geometry "matched_path"|index \["matched_path"\]).*\n/m,
        ""
      )
      |> String.replace(~r/define\(version: [\d_]+\)/, "define(version: 2026_09_23_180000)")
      |> String.replace(
        ~s("meters_between_routes" => "500"),
        ~s("meters_between_routes" => "1000")
      )
      |> String.replace(
        ~s("minutes_between_routes" => "30"),
        ~s("minutes_between_routes" => "60")
      )

    assert Base.encode16(:crypto.hash(:sha256, schema), case: :lower) ==
             "b18dd2ba70ab7e6ce030de07f725ddd2ff70424edb991f7c74ad134c743464cf"

    File.write!(Path.join(root, "schema.rb"), schema)
    runner = Path.join(root, "runner.rb")

    File.write!(runner, """
    Rails.logger = Logger.new(File::NULL)
    ActiveRecord::Schema.verbose = false
    begin
      load #{Jason.encode!(Path.join(root, "schema.rb"))}
      User.reset_column_information
      user = User.create!(email: 'cloud-source@example.test', password: 'synthetic-password', password_confirmation: 'synthetic-password', status: :trial, plan: :family, active_until: Time.utc(2030,1,8), skip_auto_trial: true, skip_family_sync: true)
      family = Family.create!(name: 'Synthetic', creator: user, access_until: Time.utc(2030,1,8))
      Family::Membership.create!(family: family, user: user, role: :owner)
      ServiceSetting.new(user: user, service: :geocoding, provider: 'synthetic', credentials: {api_key: 'synthetic'}.to_json).save!(validate: false)
      blob = ActiveStorage::Blob.create!(key: 'synthetic-l1-key', filename: 'source.txt', content_type: 'text/plain', service_name: 'local', byte_size: 1, checksum: 'synthetic')
      ActiveStorage::Attachment.create!(name: 'file', record: user, blob: blob)
      puts 'L1-SOURCE-OK'
    rescue => error
      puts 'L1-SOURCE-ERROR:' + error.class.name
      exit 1
    end
    """)

    config = ScratchRepo.config()

    {output, status} =
      System.cmd(
        System.find_executable("asdf"),
        ["exec", "bundle", "exec", "rails", "runner", runner],
        cd: Application.fetch_env!(:dawarich, :rails_root),
        env: [
          {"RAILS_ENV", "test"},
          {"DATABASE_NAME", config[:database]},
          {"DATABASE_HOST", "127.0.0.1"},
          {"REDIS_URL", Application.fetch_env!(:dawarich, :redis)[:url]},
          {"MANAGER_URL", ""},
          {"PARTNERO_API_KEY", ""},
          {"SELF_HOSTED", "false"},
          {"OTP_ENCRYPTION_PRIMARY_KEY", "synthetic-primary"},
          {"OTP_ENCRYPTION_DETERMINISTIC_KEY", "synthetic-deterministic"},
          {"OTP_ENCRYPTION_KEY_DERIVATION_SALT", "synthetic-salt"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0,
           "Rails source fixture failed: #{Enum.find(String.split(output, "\n"), &String.starts_with?(&1, "L1-SOURCE-ERROR:"))}"

    assert output =~ "L1-SOURCE-OK"

    for {directory, table} <- [{"migrate", "schema_migrations"}, {"data", "data_migrations"}] do
      versions = Dawarich.RailsTree.versions(directory) |> Enum.filter(&(&1 <= "20260923180000"))
      ScratchRepo.query!("DELETE FROM #{table}", [], log: false)

      ScratchRepo.query!("INSERT INTO #{table}(version) SELECT unnest($1::text[])", [versions],
        log: false
      )
    end
  end
end
