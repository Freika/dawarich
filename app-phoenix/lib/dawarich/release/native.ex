defmodule Dawarich.Release.Native do
  @moduledoc false

  alias Dawarich.{Release, ReleaseMigrator, ReleaseMigrations}
  alias Dawarich.ReleaseMigrator.Lease

  def ready?(repo, opts), do: ReleaseMigrator.status(repo, opts) == {:ok, :current}

  def seed(repo, opts) do
    opts = Keyword.put(opts, :rails_lock_check, false)
    require_current!(repo, opts)

    with_lock(repo, opts, fn ->
      require_current!(repo, opts)

      Lease.with_lease(repo, opts, fn lease ->
        fence!(repo, lease)
        require_current!(repo, opts)
        Dawarich.Seeds.run(repo, Keyword.put(opts, :lease, lease))
        fence!(repo, lease)
        :ok
      end)
      |> result!()
    end)
  end

  defp require_current!(repo, opts) do
    unless classify!(repo, opts) == :current and Release.readiness(opts) == :ready,
      do: refuse!(:seeds_require_current)
  end

  def migrate(repo, opts) do
    opts = Keyword.put(opts, :rails_lock_check, false)
    classify!(repo, opts)
    bootstrap_metadata(repo)

    with_lock(repo, opts, fn ->
      classify!(repo, opts)
      Release.install_schemas(repo)

      Lease.with_lease(repo, opts, fn lease ->
        fence!(repo, lease)
        classify!(repo, opts)

        case ReleaseMigrator.migrate(repo, Keyword.merge(opts, lease: lease, job_mode: :enqueue)) do
          {:ok, %{pending_data: []}} -> :ok
          {:ok, %{pending_data: versions}} -> refuse!({:pending_data, versions})
          {:error, reason} -> refuse!(reason)
        end

        fence!(repo, lease)

        case ReleaseMigrations.V1_13_1.copy_registration_setting(repo, opts) do
          {:ok, _} -> :ok
          {:error, reason} -> refuse!(reason)
        end

        fence!(repo, lease)
        :ok
      end)
      |> result!()
    end)
  end

  def with_lock(repo, opts, fun) do
    env = Keyword.get(opts, :env, System.get_env())

    if Dawarich.Visits.Persister.advisory_locks?(env["DATABASE_ADVISORY_LOCKS"]) do
      config =
        Keyword.take(repo.config(), [
          :hostname,
          :port,
          :username,
          :password,
          :database,
          :socket_dir,
          :ssl,
          :ssl_opts,
          :types,
          :parameters
        ])

      {:ok, conn} = Postgrex.start_link(config ++ [backoff_type: :stop, max_restarts: 0])

      try do
        %{rows: [[database]]} = Postgrex.query!(conn, "SELECT current_database()::text", [])
        key = 2_053_462_845 * :erlang.crc32(database)

        deadline =
          System.monotonic_time(:millisecond) + Keyword.get(opts, :lease_wait_ms, 900_000)

        acquire_lock(conn, key, opts, deadline)
        Postgrex.query!(conn, "SELECT pg_advisory_lock($1)", [key])

        try do
          fun.()
        after
          unless Postgrex.query!(
                   conn,
                   "SELECT pg_advisory_unlock($1), pg_advisory_unlock($1)",
                   [key]
                 ).rows == [[true, true]],
                 do: refuse!(:migration_lock_lost)
        end
      after
        if Process.alive?(conn), do: GenServer.stop(conn)
      end
    else
      fun.()
    end
  end

  defp acquire_lock(conn, key, opts, deadline) do
    case Postgrex.query!(conn, "SELECT pg_try_advisory_lock($1)", [key]).rows do
      [[true]] ->
        :ok

      [[false]] ->
        if System.monotonic_time(:millisecond) >= deadline, do: refuse!(:migration_lock_busy)
        sleep = Keyword.get(opts, :lease_sleep, &Process.sleep/1)
        sleep.(Keyword.get(opts, :lease_poll_ms, 2_000))
        acquire_lock(conn, key, opts, deadline)
    end
  end

  def classify!(repo, opts) do
    case ReleaseMigrator.status(repo, opts) do
      {:ok, status} -> status
      {:error, reason} -> refuse!(reason)
    end
  end

  def fence!(repo, lease) do
    unless Lease.fenced?(repo, lease), do: refuse!({:lease_lost, lease.holder})
  end

  defp bootstrap_metadata(repo) do
    repo.query!(
      "CREATE TABLE IF NOT EXISTS public.schema_migrations (version varchar NOT NULL PRIMARY KEY)",
      [],
      log: false
    )

    repo.query!(
      "CREATE TABLE IF NOT EXISTS public.ar_internal_metadata (key varchar NOT NULL PRIMARY KEY, value varchar, created_at timestamp(6) NOT NULL, updated_at timestamp(6) NOT NULL)",
      [],
      log: false
    )
  end

  defp result!({:error, reason}), do: refuse!(reason)
  defp result!(result), do: result
  defp refuse!(reason), do: raise(Dawarich.CLI.Migrate.describe(reason))
end
