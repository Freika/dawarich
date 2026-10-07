defmodule Dawarich.ReleaseCloudTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Release, ReleaseMigration, Repo}

  defp role do
    database = Application.fetch_env!(:dawarich, Repo)[:database]
    suffix = :crypto.hash(:sha256, database) |> Base.encode16(case: :lower) |> binary_part(0, 20)
    "dawarich_phoenix_nocreate_" <> suffix
  end

  @password "nocreate"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
  end

  @cloud_env %{
    "SELF_HOSTED" => "false",
    "DAWARICH_PHOENIX_LIFECYCLE" => "true",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-admission-key",
    "DATABASE_SESSION_URL" => "postgres://session.example.invalid/cloud"
  }

  for {name, key, value} <- [
        {"Manager origin", "MANAGER_URL", nil},
        {"JWT signing secret", "JWT_SECRET_KEY", " \t"},
        {"dedicated session URL", "DATABASE_SESSION_URL", nil},
        {"direct session endpoint", "DATABASE_SESSION_URL",
         "postgres://session.example.invalid:6432/cloud"},
        {"HTTPS Manager", "MANAGER_URL", "http://manager.example.invalid"},
        {"explicit Cloud mode", "SELF_HOSTED", "off"},
        {"source drain isolation", "DAWARICH_CLOUD_DRAIN_ONLY", "true"}
      ] do
    test "native Cloud admission refuses missing #{name}" do
      assert Dawarich.Release.Lifecycle.mode(@cloud_env) == {:ok, :native}
      before = refusal_snapshot()
      invalid = Map.put(@cloud_env, unquote(key), unquote(value))

      for env <- [invalid, Map.put(invalid, "DAWARICH_RAILS", "off")] do
        opts = Keyword.put(copy_opts(), :env, env)
        assert Dawarich.Release.Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}

        for command <- [&Release.migrate/1, &Release.seed/1] do
          assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, fn ->
            command.(opts)
          end
        end

        for command <- [&Dawarich.Release.Native.migrate/2, &Dawarich.Release.Native.seed/2] do
          assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, fn ->
            command.(Repo, opts)
          end
        end

        assert Release.readiness(opts) == :schemas_behind

        assert refusal_snapshot() == before
      end
    end
  end

  test "native Cloud admission requires a valid session URL and origin in every mode" do
    assert Dawarich.Release.Lifecycle.mode(@cloud_env) == {:ok, :native}

    for mode <- ["off", "proxy"],
        {key, values} <- [
          {"DATABASE_SESSION_URL",
           [
             "",
             " ",
             "garbage",
             "http://db.invalid/cloud",
             "postgres://db.invalid",
             "postgres://db.invalid/cloud?pool_mode=transaction",
             "postgres://db.invalid/cloud#fragment"
           ]},
          {"MANAGER_URL",
           [
             "",
             " ",
             "https://user:password@manager.example.invalid",
             "https://manager.example.invalid/path",
             "https://manager.example.invalid?query",
             "https://manager.example.invalid#fragment"
           ]}
        ],
        value <- values do
      env = @cloud_env |> Map.put("DAWARICH_RAILS", mode) |> Map.put(key, value)
      assert Dawarich.Release.Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}
    end
  end

  test "B3 invalid public and direct Cloud calls preserve complete public private and registration rows" do
    assert {:error, :snapshot_complete} =
             Repo.transaction(fn ->
               Repo.query!(
                 "INSERT INTO phoenix.registration_setting(id,enabled) VALUES(true,false) ON CONFLICT(id) DO NOTHING"
               )

               invalids =
                 [
                   %{"SELF_HOSTED" => "false", "DAWARICH_RAILS" => "off"},
                   Map.put(@cloud_env, "DATABASE_SESSION_URL", "postgres://db.invalid/%20"),
                   Map.merge(@cloud_env, %{
                     "DATABASE_URL" => @cloud_env["DATABASE_SESSION_URL"],
                     "DATABASE_POOLING_MODE" => "transaction"
                   })
                 ] ++
                   Enum.map(
                     ~w(MANAGER_URL JWT_SECRET_KEY DATABASE_SESSION_URL),
                     &Map.delete(@cloud_env, &1)
                   )

               before = refusal_snapshot()

               for invalid <- invalids, mode <- ["off", "proxy"] do
                 env = Map.put(invalid, "DAWARICH_RAILS", mode)
                 env = Map.put(env, "DAWARICH_PHOENIX_LIFECYCLE", "true")
                 assert Dawarich.Release.Lifecycle.mode(env) == {:error, :cloud_native_lifecycle}
                 opts = Keyword.put(copy_opts(), :env, env)

                 for command <- [
                       fn -> Release.migrate(opts) end,
                       fn -> Release.seed(opts) end,
                       fn -> Dawarich.Release.Native.migrate(Repo, opts) end,
                       fn -> Dawarich.Release.Native.seed(Repo, opts) end
                     ] do
                   assert_raise RuntimeError,
                                ~r/native lifecycle requires self-hosted mode/,
                                command

                   assert refusal_snapshot() == before
                 end

                 assert Release.readiness(opts) == :schemas_behind
                 assert refusal_snapshot() == before
               end

               Repo.rollback(:snapshot_complete)
             end)
  end

  defp refusal_snapshot do
    for table <-
          ~w(public.schema_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations phoenix.registration_setting) do
      {table,
       Repo.query!("SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text").rows}
    end
  end

  describe "readiness/0" do
    test "is :ready once both ledgers record every migration in the release" do
      assert Release.migrate(copy_opts()) == :ok
      assert Release.readiness() == :ready
    end

    test "is :schemas_behind while an Oban migration is unrecorded" do
      assert Release.migrate(copy_opts()) == :ok
      Repo.query!("DELETE FROM oban.phoenix_schema_migrations")

      assert Release.readiness() == :schemas_behind

      assert Release.migrate(copy_opts()) == :ok
      assert Release.readiness() == :ready
    end

    test "is :schemas_behind without the phoenix ledger and does not create it" do
      assert Release.migrate(copy_opts()) == :ok
      Repo.query!("DROP TABLE phoenix.phoenix_schema_migrations")
      on_exit(&restore_schemas_and_role/0)

      assert Release.readiness() == :schemas_behind
      refute relation?("phoenix.phoenix_schema_migrations")
    end

    @tag capture_log: true
    test "is :no_connection when PostgreSQL does not answer" do
      pool =
        start_supervised!(
          {Repo,
           name: nil,
           pool: DBConnection.ConnectionPool,
           pool_size: 1,
           hostname: "127.0.0.1",
           port: 1}
        )

      assert with_pool(pool, &Release.readiness/0) == :no_connection
    end

    test "never waits for the migration table lock a real migration run holds" do
      assert Release.migrate(copy_opts()) == :ok

      parent = self()

      holder =
        spawn(fn ->
          Repo.transaction(
            fn ->
              Repo.query!(
                "LOCK TABLE phoenix.phoenix_schema_migrations IN SHARE UPDATE EXCLUSIVE MODE"
              )

              send(parent, :locked)

              receive do
                :release -> :ok
              end
            end,
            timeout: :infinity
          )
        end)

      on_exit(fn ->
        ref = Process.monitor(holder)
        send(holder, :release)

        receive do
          {:DOWN, ^ref, :process, ^holder, _} -> :ok
        after
          2_000 -> :ok
        end
      end)

      assert_receive :locked, 2_000

      task = Task.async(&Release.readiness/0)
      assert Task.yield(task, 2_000) == {:ok, :ready}
    end
  end

  describe "a role without CREATE on the database" do
    setup do
      drop_schemas_and_role()
      Repo.query!("CREATE ROLE #{role()} LOGIN PASSWORD '#{@password}'")
      on_exit(&restore_schemas_and_role/0)

      pool =
        start_supervised!(
          {Repo,
           name: nil,
           pool: DBConnection.ConnectionPool,
           pool_size: 2,
           username: role(),
           password: @password}
        )

      %{pool: pool}
    end

    test "migrates once both schemas exist and belong to it", %{pool: pool} do
      fixture =
        Path.expand("../fixtures/auth/activation.json", __DIR__)
        |> File.read!()
        |> Jason.decode!()

      for {name, value} <- [{"false", false}, {"nil", nil}] do
        Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")
        Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE")
        Repo.query!("CREATE SCHEMA phoenix AUTHORIZATION #{role()}")
        Repo.query!("CREATE SCHEMA oban AUTHORIZATION #{role()}")
        source = Base.decode64!(fixture["registration"][name])

        assert with_pool(pool, fn ->
                 assert Repo.query!(
                          "SELECT has_database_privilege(current_user, current_database(), 'CREATE')"
                        ).rows == [[false]]

                 Release.migrate(command: fn _ -> {:ok, source} end)
               end) == :ok

        assert with_pool(pool, fn ->
                 Repo.query!("SELECT enabled FROM phoenix.registration_setting").rows
               end) == [[value]]

        assert with_pool(pool, &Release.readiness/0) == :ready
      end
    end

    test "cannot migrate while the schemas are missing and reports them behind", %{pool: pool} do
      error =
        assert_raise Postgrex.Error, fn ->
          with_pool(pool, fn -> Release.migrate(copy_opts()) end)
        end

      assert error.postgres.code == :insufficient_privilege
      assert with_pool(pool, &Release.readiness/0) == :schemas_behind
    end
  end

  test "cloud schema cleanup leaves a later recovery mail consumer able to enqueue" do
    assert Release.migrate(copy_opts()) == :ok
    Repo.query!("DROP TABLE phoenix.phoenix_schema_migrations")
    restore_schemas_and_role()

    notification = %Dawarich.Auth.Recovery.Notification{
      kind: :reset_password_instructions,
      user_id: 1,
      raw: "schema-isolation-token",
      digest: "schema-isolation-digest",
      locale: "en"
    }

    assert {:error, :probe_complete} =
             Repo.transaction(fn ->
               assert :ok = Dawarich.Auth.Recovery.MailWorker.enqueue(notification)

               assert Repo.query!(
                        "SELECT queue FROM oban.oban_jobs WHERE args->>'digest'=$1",
                        [notification.digest]
                      ).rows == [["mailers"]]

               Repo.rollback(:probe_complete)
             end)

    assert Release.readiness() == :ready
  end

  test "Oban peers lead only with a per-container node name taken from HOSTNAME" do
    previous = System.get_env("HOSTNAME")
    System.put_env("HOSTNAME", "3f2a9c1d7b44")

    try do
      oban =
        Config.Reader.read!(Path.expand("../../config/runtime.exs", __DIR__), env: :prod)[
          :dawarich
        ][Oban]

      assert oban[:node] == "3f2a9c1d7b44"
      assert oban[:peer] == Oban.Peers.Database
    after
      if previous, do: System.put_env("HOSTNAME", previous), else: System.delete_env("HOSTNAME")
    end
  end

  test "release.sh tells a Cloud deploy from a self-hosted one by ReleaseMigration.self_hosted?/0's rule" do
    docker = Path.expand("../../../docker", __DIR__)
    decision = ~S(env_value_is_truthy "${SELF_HOSTED-true}")
    previous = System.get_env("SELF_HOSTED")

    assert File.read!(Path.join(docker, "release.sh")) =~ decision

    try do
      for value <-
            [nil, "", "true", "TRUE", " yes ", "1", "on", "t", ~s("true"), "'false'"] ++
              ["false", "0", "no", "off", "tru"] do
        if value, do: System.put_env("SELF_HOSTED", value), else: System.delete_env("SELF_HOSTED")

        {_, status} =
          System.cmd("sh", [
            "-c",
            ~S(. "$0"; ) <> decision,
            Path.join(docker, "entrypoint-env-guard.sh")
          ])

        assert status == 0 == ReleaseMigration.self_hosted?(), "SELF_HOSTED=#{inspect(value)}"
      end
    after
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end
  end

  defp with_pool(pool, fun) do
    Repo.put_dynamic_repo(pool)
    fun.()
  after
    Repo.put_dynamic_repo(Repo)
  end

  defp restore_schemas_and_role do
    drop_schemas_and_role()
    Release.migrate(copy_opts())
  end

  defp drop_schemas_and_role do
    Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE")
    Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")

    Repo.query!("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{role()}') THEN
        DROP OWNED BY #{role()};
        DROP ROLE #{role()};
      END IF;
    END
    $$
    """)
  end

  defp relation?(name) do
    %{rows: [[found]]} = Repo.query!("SELECT to_regclass($1) IS NOT NULL", [name])
    found
  end

  defp copy_opts, do: [command: fn _ -> {:ok, nil} end, env: %{}]
end

defmodule Dawarich.ReleaseCloudCompatibilityTest.Pending do
  def release, do: "cloud-pending-proof"
  def steps, do: []
  def data_versions, do: ["20991006000001"]
end

defmodule Dawarich.ReleaseCloudCompatibilityTest do
  use Dawarich.ScratchCase, async: false

  alias Dawarich.{ActiveRecordEncryption, Release, Repo, Storage}
  alias Dawarich.Release.Native

  @source_version "20260923180000"
  @source_schema_digest "b18dd2ba70ab7e6ce030de07f725ddd2ff70424edb991f7c74ad134c743464cf"
  @encryption %{
    "RAILS_ENV" => "test",
    "OTP_ENCRYPTION_PRIMARY_KEY" => "cloud-compatibility-primary-fixture",
    "OTP_ENCRYPTION_DETERMINISTIC_KEY" => "cloud-compatibility-deterministic-fixture",
    "OTP_ENCRYPTION_KEY_DERIVATION_SALT" => "cloud-compatibility-salt-fixture"
  }

  setup do
    for schema <- ~w(phoenix oban),
        do: ScratchRepo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE")

    Dawarich.MigrationModules.purge()
    root = Path.join(System.tmp_dir!(), "release-cloud-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)
      Dawarich.ScratchCase.recreate_public!(ScratchRepo)

      for schema <- ~w(phoenix oban),
          do: ScratchRepo.query!("DROP SCHEMA IF EXISTS #{schema} CASCADE")

      Dawarich.MigrationModules.purge()
      Release.migrate(repo: ScratchRepo, env: %{}, command: fn _ -> {:ok, nil} end)
    end)

    %{root: root}
  end

  test "native upgrade preserves Rails1153 rows while an accepted source job completes on shared SQL",
       %{root: root} do
    fixture = source_fixture!(root)

    tables =
      ~w(users imports trips points service_settings active_storage_blobs active_storage_attachments)

    before = snapshot(tables)
    ledger = ScratchRepo.query!("SELECT version FROM schema_migrations ORDER BY version").rows
    refute relation?("public.job_outbox")

    assert :ok = Release.migrate(opts())
    assert relation?("public.job_outbox")
    assert snapshot(tables) == before

    assert ledger --
             ScratchRepo.query!("SELECT version FROM schema_migrations ORDER BY version").rows ==
             []

    assert Release.readiness(opts()) == :ready

    data_version = hd(__MODULE__.Pending.data_versions())

    pending_opts =
      Keyword.put(opts(), :releases, Dawarich.ReleaseMigrations.all() ++ [__MODULE__.Pending])

    ScratchRepo.query!("DELETE FROM data_migrations WHERE version=$1", [data_version])

    ready_before =
      snapshot(
        ~w(schema_migrations data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations oban.oban_jobs)
      )

    assert Release.readiness(pending_opts) == :schemas_behind

    assert snapshot(
             ~w(schema_migrations data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations oban.oban_jobs)
           ) == ready_before

    ScratchRepo.query!("INSERT INTO data_migrations(version) VALUES($1)", [data_version])

    {:ok, key} = ActiveRecordEncryption.key(@encryption)
    [[ciphertext]] = ScratchRepo.query!("SELECT credentials FROM service_settings").rows

    assert {:ok, ~s({"api_key":"synthetic-source"})} =
             ActiveRecordEncryption.decrypt(ciphertext, key)

    native = ActiveRecordEncryption.encrypt(~s({"api_key":"synthetic-native"}), key)
    ScratchRepo.query!("UPDATE service_settings SET credentials=$1", [native])

    ScratchRepo.query!(
      "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1700000002,ST_SetSRID(ST_MakePoint(13.402,52.502),4326),now(),now())",
      [fixture["user"], fixture["import"]]
    )

    result =
      rails!(
        root,
        """
        import = Import.find(#{fixture["import"]})
        trip = Trip.find(#{fixture["trip"]})
        raise 'native ciphertext unreadable' unless ServiceSetting.first.credentials_hash.fetch('api_key') == 'synthetic-native'
        require 'sidekiq/api'
        queued = Sidekiq::Queue.new('imports').find_job('#{fixture["jid"]}')
        raise 'accepted job missing' unless queued
        count = Sidekiq::Queue.new('imports').size
        ActiveJob::Base.execute(queued.args.fetch(0))
        queued.delete
        raise 'source continuation appeared' unless Sidekiq::Queue.new('imports').size == count - 1
        puts 'COMPAT:' + {processed: import.reload.processed, points: import.points.count, trip: trip.name, email: import.user.email}.to_json
        """,
        true
      )

    assert result == %{
             "processed" => 3,
             "points" => 3,
             "trip" => "source-trip",
             "email" => "source@example.test"
           }

    after_effect = snapshot(tables)
    assert Release.migrate(opts()) == :ok
    assert snapshot(tables) == after_effect
    assert Release.readiness(opts()) == :ready

    public_version = "20260927120000"
    ScratchRepo.query!("DELETE FROM schema_migrations WHERE version=$1", [public_version])
    assert Release.readiness(opts()) == :schemas_behind
    assert relation?("public.job_outbox")
  end

  test "shared signed attachment remains readable by Rails1153 after a native write and source drain",
       %{root: root} do
    fixture = source_fixture!(root)
    assert :ok = Release.migrate(opts())
    before = snapshot(~w(active_storage_blobs active_storage_attachments users))
    cloud_opts = Keyword.put(opts(), :env, %{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "false"})

    assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, fn ->
      Native.seed(ScratchRepo, cloud_opts)
    end

    assert snapshot(~w(active_storage_blobs active_storage_attachments users)) == before

    bytes = "native attachment\n"
    key = Storage.generate_key()
    path = Storage.disk_path(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    File.chmod!(path, 0o640)

    blob = %{
      key: key,
      filename: "native.bin",
      content_type: "application/octet-stream",
      metadata: "{}",
      service_name: "local",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes))
    }

    id =
      Dawarich.Storage.Blobs.attach!(
        ScratchRepo,
        "Import",
        fixture["import"],
        blob,
        NaiveDateTime.utc_now()
      )

    signed = Dawarich.RailsMessages.blob_id(id)
    attachments = snapshot(~w(active_storage_blobs active_storage_attachments))

    result =
      rails!(
        root,
        """
        require 'sidekiq/api'
        queued = Sidekiq::Queue.new('imports').find_job('#{fixture["jid"]}')
        raise 'accepted job missing' unless queued
        count = Sidekiq::Queue.new('imports').size
        ActiveJob::Base.execute(queued.args.fetch(0))
        queued.delete
        raise 'source continuation appeared' unless Sidekiq::Queue.new('imports').size == count - 1
        signed = #{Jason.encode!(signed)}
        blob = ActiveStorage::Blob.find_signed!(signed)
        raise 'attachment missing' unless blob.attachments.exists?(record_type: 'Import', record_id: #{fixture["import"]})
        raise 'object bytes changed' unless blob.download == "native attachment\\n"
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.host! 'www.example.com'
        session.get("/rails/active_storage/blobs/proxy/\#{signed}/native.bin")
        raise 'signed route unreadable' unless session.response.status == 200 && session.response.body == blob.download
        source = ActiveStorage::Blob.where.not(id: blob.id).first!
        raise 'source attachment changed' unless source.download == 'source attachment'
        puts 'COMPAT:' + {key: blob.key, checksum: blob.checksum, service: blob.service_name, bytes: session.response.body, processed: Import.find(#{fixture["import"]}).processed, source_signed: source.signed_id}.to_json
        """,
        true
      )

    assert Map.take(result, ~w(key checksum service bytes processed)) == %{
             "key" => key,
             "checksum" => blob.checksum,
             "service" => "local",
             "bytes" => bytes,
             "processed" => 2
           }

    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o640
    assert snapshot(~w(active_storage_blobs active_storage_attachments)) == attachments

    previous = Repo.get_dynamic_repo()
    Repo.put_dynamic_repo(ScratchRepo)

    try do
      for {token, expected} <- [{signed, bytes}, {result["source_signed"], "source attachment"}] do
        conn =
          Plug.Test.conn(:get, "/rails/active_storage/blobs/proxy/" <> token <> "/native.bin")

        conn = %{conn | path_params: %{"signed_id" => token}}

        response =
          DawarichWeb.ActiveStorage.Proxy.call(conn,
            storage: %{default: "local", services: %{"local" => %{service: "local", root: root}}}
          )

        assert response.status == 200
        assert response.resp_body == expected
      end
    after
      Repo.put_dynamic_repo(previous)
    end
  end

  defp source_fixture!(root) do
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

    assert Base.encode16(:crypto.hash(:sha256, schema), case: :lower) == @source_schema_digest
    schema_path = Path.join(root, "source-schema.rb")
    File.write!(schema_path, schema)

    fixture =
      rails!(root, """
      ActiveRecord::Schema.verbose = false
      load #{Jason.encode!(schema_path)}
      User.reset_column_information
      user = User.new(email: 'source@example.test', password: 'source-password', password_confirmation: 'source-password', skip_auto_trial: true)
      user.save!
      import = Import.new(user: user, name: 'source-import', source: :gpx, skip_background_processing: true)
      import.save!
      trip = Trip.create!(user: user, name: 'source-trip', started_at: Time.at(1700000000), ended_at: Time.at(1700000060), skip_calculation_enqueue: true)
      2.times do |i|
        Point.create!(user: user, import: import, timestamp: 1700000000 + i, lonlat: "POINT(#{13.4} #{52.5})".sub('13.4', (13.4 + i * 0.001).to_s))
      end
      setting = ServiceSetting.new(user: user, service: :geocoding, provider: 'compatibility', credentials: {api_key: 'synthetic-source'}.to_json)
      setting.save!(validate: false)
      import.file.attach(io: StringIO.new('source attachment'), filename: 'source.txt', content_type: 'text/plain')
      accepted = Import::UpdatePointsCountJob.perform_later(import.id)
      puts 'COMPAT:' + {user: user.id, import: import.id, trip: trip.id, jid: accepted.provider_job_id}.to_json
      """)

    for {directory, table} <- [{"migrate", "schema_migrations"}, {"data", "data_migrations"}] do
      versions = Dawarich.RailsTree.versions(directory) |> Enum.filter(&(&1 <= @source_version))
      ScratchRepo.query!("DELETE FROM #{table}")
      ScratchRepo.query!("INSERT INTO #{table}(version) SELECT unnest($1::text[])", [versions])
    end

    fixture
  end

  defp rails!(root, script, drain \\ false) do
    database =
      System.fetch_env!("PHOENIX_TEST_DATABASE") <>
        System.get_env("MIX_TEST_PARTITION", "") <> "_scratch_case"

    unless database == ScratchRepo.config()[:database],
      do: raise("allocated private test DB required")

    path = Path.join(root, "runner.rb")

    File.write!(path, """
    Rails.logger = Logger.new(File::NULL)
    ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new({'local' => {'service' => 'Disk', 'root' => #{Jason.encode!(root)}}})
    ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch('local')
    begin
    #{script}
    rescue => e
      puts 'COMPAT-ERROR:' + e.class.name
      exit 1
    end
    """)

    env =
      Enum.to_list(@encryption) ++
        [
          {"RAILS_ENV", "test"},
          {"DATABASE_NAME", database},
          {"DATABASE_HOST", "127.0.0.1"},
          {"REDIS_URL", Application.fetch_env!(:dawarich, :redis)[:url]},
          {"SECRET_KEY_BASE", Dawarich.RailsSecret.fetch()},
          {"SELF_HOSTED", "false"},
          {"DAWARICH_CLOUD_DRAIN_ONLY", if(drain, do: "true", else: "false")},
          {"DAWARICH_RAILS", "on"}
        ]

    {executable, args} =
      case System.find_executable("asdf") do
        nil -> {"bundle", ["exec", "rails", "runner", path]}
        asdf -> {asdf, ["exec", "bundle", "exec", "rails", "runner", path]}
      end

    {output, status} =
      System.cmd(executable, args,
        cd: Application.fetch_env!(:dawarich, :rails_root),
        env: env,
        stderr_to_stdout: true
      )

    error =
      Enum.find(String.split(output, "\n"), &Regex.match?(~r/^COMPAT-ERROR:[A-Za-z:]+$/, &1))

    assert status == 0, "source runner failed (#{status}): #{error}"

    output
    |> String.split("\n")
    |> Enum.find(&String.starts_with?(&1, "COMPAT:"))
    |> String.replace_prefix("COMPAT:", "")
    |> Jason.decode!()
  end

  defp opts,
    do: [
      repo: ScratchRepo,
      env: %{"DAWARICH_PHOENIX_LIFECYCLE" => "true", "SELF_HOSTED" => "true"},
      command: fn _ -> {:ok, nil} end
    ]

  defp snapshot(tables),
    do:
      Enum.map(tables, fn table ->
        ScratchRepo.query!("SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text").rows
      end)

  defp relation?(name),
    do: ScratchRepo.query!("SELECT to_regclass($1) IS NOT NULL", [name]).rows == [[true]]
end

defmodule Dawarich.ReleaseCloudAdmissionTest do
  use Dawarich.ScratchCase, async: false
  alias Dawarich.Release
  alias Dawarich.Release.Native

  @env %{
    "SELF_HOSTED" => "false",
    "DAWARICH_PHOENIX_LIFECYCLE" => "true",
    "MANAGER_URL" => "https://manager.example.invalid",
    "JWT_SECRET_KEY" => "synthetic-public-cloud",
    "TIME_ZONE" => "Europe/Berlin"
  }
  @now ~N[2026-10-07 12:00:00.000000]

  setup do
    previous = System.get_env("SELF_HOSTED")
    System.put_env("SELF_HOSTED", "false")
    Dawarich.MigrationModules.purge()

    for schema <- ~w(phoenix oban) do
      sql("DROP SCHEMA IF EXISTS #{schema} CASCADE")
      sql("CREATE SCHEMA #{schema}")
    end

    for extension <- ~w(postgis pgcrypto),
        do: sql("CREATE EXTENSION IF NOT EXISTS #{extension}")

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

  test "native Cloud release provisions precreated schemas without database CREATE" do
    role = "l1_public_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    password = "synthetic-public-role"
    sql("CREATE ROLE #{role} LOGIN PASSWORD '#{password}'")

    for schema <- ~w(public phoenix oban),
        do: sql("ALTER SCHEMA #{schema} OWNER TO #{role}")

    pool =
      start_supervised!(
        {ScratchRepo, name: nil, pool_size: 3, username: role, password: password}
      )

    on_exit(fn ->
      sql("DROP OWNED BY #{role} CASCADE")
      sql("DROP ROLE #{role}")

      for schema <- ~w(public phoenix oban),
          do: sql("CREATE SCHEMA IF NOT EXISTS #{schema}")
    end)

    previous = ScratchRepo.get_dynamic_repo()
    ScratchRepo.put_dynamic_repo(pool)
    config = Keyword.merge(ScratchRepo.config(), username: role, password: password)
    opts = opts(config: config)

    try do
      assert sql("SELECT has_database_privilege(current_user,current_database(),'CREATE')") == [
               [false]
             ]

      assert :ok = Release.migrate(opts)
      assert Release.readiness(opts) == :ready
      before = snapshot()

      assert :ok =
               Release.migrate(Keyword.update!(opts, :env, &Map.put(&1, "DAWARICH_RAILS", "off")))

      assert :ok = Native.migrate(ScratchRepo, opts)
      assert snapshot() == before
    after
      ScratchRepo.put_dynamic_repo(previous)
    end
  end

  test "native Cloud web readiness is read only and refuses missing public or private versions" do
    opts = opts()
    assert :ok = Release.migrate(opts)
    assert Release.readiness(opts) == :ready
    sql("DELETE FROM public.ar_internal_metadata WHERE key='phoenix_native_baseline'")

    sql("INSERT INTO public.data_migrations(version) SELECT unnest($1::text[])", [
      Dawarich.RailsTree.versions("data")
    ])

    assert Release.readiness(opts) == :ready
    parent = self()
    telemetry = {__MODULE__, make_ref()}

    :telemetry.attach(
      telemetry,
      [:dawarich, :scratch_case_repo, :query],
      fn _, _, meta, _ ->
        if self() == parent, do: send(parent, {:readiness_sql, meta.query})
      end,
      nil
    )

    try do
      for table <-
            ~w(public.schema_migrations public.data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations) do
        [[removed]] =
          sql(
            "DELETE FROM #{table} WHERE version=(SELECT max(version) FROM #{table}) RETURNING row_to_json(#{List.last(String.split(table, "."))})"
          )

        flush_queries()
        before = snapshot()
        flush_queries()
        assert Release.readiness(opts) == :schemas_behind
        queries = flush_queries()
        assert queries != []
        assert Enum.all?(queries, &String.starts_with?(String.trim(&1), "SELECT"))
        assert snapshot() == before

        sql("INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table},$1)", [
          removed
        ])

        assert Release.readiness(opts) == :ready
      end

      sql(
        "INSERT INTO phoenix.release_operations(id,command_type,cursor,status) VALUES($1,'release.family_backfill','{}','failed')",
        [Ecto.UUID.dump!(Ecto.UUID.generate())]
      )

      flush_queries()
      assert Release.readiness(opts) == :schemas_behind
      assert Enum.all?(flush_queries(), &String.starts_with?(String.trim(&1), "SELECT"))
    after
      :telemetry.detach(telemetry)
    end
  end

  test "native Cloud provisioning preserves source trial family and callback effects exactly across reentry" do
    opts = opts()
    assert :ok = Release.migrate(opts)
    assert :ok = Release.seed(seed_opts(opts))
    assert sql("SELECT count(*) FROM users") == [[0]]

    [[user]] =
      sql(
        "INSERT INTO users(email,created_at,updated_at) VALUES('public-cloud@example.test',$1,$1) RETURNING id",
        [@now]
      )

    for type <- ~w(mail.user.welcome users.explore_features_mail users.creation_webhook),
        do: Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:" <> type, :oban)

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.Users.CreationEffects.apply(ScratchRepo, user, env: opts[:env], now: @now)
             end)

    assert sql("SELECT admin,status,active_until,length(api_key) FROM users WHERE id=$1", [user]) ==
             [[false, 2, ~N[2026-10-14 12:00:00.000000], 64]]

    assert sql("SELECT count(*) FROM job_outbox WHERE aggregate_id=$1", [user]) == [[3]]

    [[family]] =
      sql(
        "INSERT INTO families(name,creator_id,access_until,created_at,updated_at) VALUES('Synthetic source family',$1,'2027-01-01',$2,$2) RETURNING id",
        [user, @now]
      )

    sql(
      "INSERT INTO family_memberships(family_id,user_id,role,created_at,updated_at) VALUES($1,$2,0,$3,$3)",
      [family, user, @now]
    )

    before =
      snapshot() ++ sql("SELECT status,plan,active_until,api_key FROM users WHERE id=$1", [user])

    for _ <- 1..2 do
      assert :ok = Release.migrate(opts)
      assert :ok = Release.seed(seed_opts(opts))
      assert :ok = Native.seed(ScratchRepo, seed_opts(opts))

      assert snapshot() ++
               sql("SELECT status,plan,active_until,api_key FROM users WHERE id=$1", [user]) ==
               before
    end
  end

  test "public and direct Cloud provisioning refuse incomplete schemas before effects" do
    opts = opts()
    sql("DROP SCHEMA phoenix CASCADE")
    before = sql("SELECT count(*) FROM pg_class")

    for command <- [
          fn -> Release.migrate(opts) end,
          fn -> Release.seed(opts) end,
          fn -> Native.migrate(ScratchRepo, opts) end,
          fn -> Native.seed(ScratchRepo, opts) end
        ] do
      assert_raise RuntimeError, ~r/native lifecycle requires self-hosted mode/, command
    end

    assert Release.readiness(opts) == :schemas_behind
    assert sql("SELECT count(*) FROM pg_class") == before
    sql("CREATE SCHEMA phoenix")
    assert :ok = Release.migrate(opts)
  end

  defp opts(extra \\ []) do
    config = extra[:config] || ScratchRepo.config()

    uri = %URI{
      scheme: "postgres",
      host: config[:hostname],
      port: config[:port],
      path: "/" <> config[:database],
      userinfo:
        URI.encode_www_form(config[:username]) <>
          ":" <> URI.encode_www_form(config[:password] || "")
    }

    [
      repo: ScratchRepo,
      env: Map.put(@env, "DATABASE_SESSION_URL", URI.to_string(uri)),
      command: fn _ -> {:ok, nil} end,
      now: @now
    ]
  end

  defp seed_opts(opts) do
    c = Dawarich.A12hSeeds.case!("A12h_fresh")
    priv = Dawarich.A12hSeeds.country_priv!(c["sources"]["countries"])
    asset = Path.join(priv, "regions.json")
    File.write!(asset, Jason.encode!(c["sources"]["regions"]))
    Keyword.merge(opts, priv_dir: priv, asset: asset)
  end

  defp snapshot do
    for table <-
          ~w(public.schema_migrations public.data_migrations phoenix.phoenix_schema_migrations oban.phoenix_schema_migrations phoenix.registration_setting job_outbox families family_memberships phoenix.processed_commands) do
      {table, sql("SELECT row_to_json(t) FROM #{table} t ORDER BY row_to_json(t)::text")}
    end
  end

  defp flush_queries(acc \\ []) do
    receive do
      {:readiness_sql, query} -> flush_queries([query | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp sql(query, params \\ []), do: ScratchRepo.query!(query, params, log: false).rows
end
