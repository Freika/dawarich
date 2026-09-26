defmodule Dawarich.ReleaseCloudTest do
  use ExUnit.Case, async: false

  alias Dawarich.{Release, Repo}

  @role "dawarich_phoenix_nocreate"
  @password "nocreate"

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, :auto)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual) end)
  end

  describe "readiness/0" do
    test "is :ready once both ledgers record every migration in the release" do
      assert Release.migrate() == :ok
      assert Release.readiness() == :ready
    end

    test "is :schemas_behind while an Oban migration is unrecorded" do
      assert Release.migrate() == :ok
      Repo.query!("DELETE FROM oban.phoenix_schema_migrations")

      assert Release.readiness() == :schemas_behind

      assert Release.migrate() == :ok
      assert Release.readiness() == :ready
    end

    test "is :schemas_behind without the phoenix ledger and does not create it" do
      assert Release.migrate() == :ok
      Repo.query!("DROP TABLE phoenix.phoenix_schema_migrations")
      on_exit(&drop_schemas_and_role/0)

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
      assert Release.migrate() == :ok

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
      Repo.query!("CREATE ROLE #{@role} LOGIN PASSWORD '#{@password}'")
      on_exit(&drop_schemas_and_role/0)

      pool =
        start_supervised!(
          {Repo,
           name: nil,
           pool: DBConnection.ConnectionPool,
           pool_size: 2,
           username: @role,
           password: @password}
        )

      %{pool: pool}
    end

    test "migrates once both schemas exist and belong to it", %{pool: pool} do
      Repo.query!("CREATE SCHEMA phoenix AUTHORIZATION #{@role}")
      Repo.query!("CREATE SCHEMA oban AUTHORIZATION #{@role}")

      assert with_pool(pool, &Release.migrate/0) == :ok
      assert with_pool(pool, &Release.readiness/0) == :ready
    end

    test "cannot migrate while the schemas are missing and reports them behind", %{pool: pool} do
      error = assert_raise Postgrex.Error, fn -> with_pool(pool, &Release.migrate/0) end

      assert error.postgres.code == :insufficient_privilege
      assert with_pool(pool, &Release.readiness/0) == :schemas_behind
    end
  end

  test "Oban peers stay off until each container has its own node name" do
    config = Application.fetch_env!(:dawarich, Oban)

    assert config[:peer] == false or is_binary(config[:node])
  end

  defp with_pool(pool, fun) do
    Repo.put_dynamic_repo(pool)
    fun.()
  after
    Repo.put_dynamic_repo(Repo)
  end

  defp drop_schemas_and_role do
    Repo.query!("DROP SCHEMA IF EXISTS oban CASCADE")
    Repo.query!("DROP SCHEMA IF EXISTS phoenix CASCADE")

    Repo.query!("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '#{@role}') THEN
        DROP OWNED BY #{@role};
        DROP ROLE #{@role};
      END IF;
    END
    $$
    """)
  end

  defp relation?(name) do
    %{rows: [[found]]} = Repo.query!("SELECT to_regclass($1) IS NOT NULL", [name])
    found
  end
end
