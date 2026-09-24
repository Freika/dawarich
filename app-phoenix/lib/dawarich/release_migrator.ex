defmodule Dawarich.ReleaseMigrator do
  @moduledoc false

  alias Dawarich.{ReleaseMigration, ReleaseMigrations}
  alias Dawarich.ReleaseMigrator.{Lease, Ledger}

  @rails_migrator_salt 2_053_462_845

  @preflight_sql """
  SELECT current_setting('TimeZone'), current_schema()::text,
         ARRAY(SELECT n.nspname::text FROM pg_class c
               JOIN pg_namespace n ON n.oid = c.relnamespace
               WHERE c.relname = 'schema_migrations' AND c.relkind IN ('r', 'p')
                 AND n.nspname <> 'public' ORDER BY 1)
  """

  @rails_lock_sql """
  SELECT pid FROM pg_locks
  WHERE locktype = 'advisory' AND granted AND objsubid = 1 AND pid <> pg_backend_pid()
    AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
    AND classid::bigint = $1 AND objid::bigint = $2
  """

  def migrate(repo, opts \\ []) do
    releases = Keyword.get_lazy(opts, :releases, &ReleaseMigrations.all/0)

    with :ok <- preflight(repo) do
      Lease.with_lease(repo, opts, fn lease ->
        run(repo, lease, releases, Keyword.get(opts, :baseline), [])
      end)
    end
  end

  def apply_release(repo, module, opts \\ []) do
    with :ok <- preflight(repo) do
      Lease.with_lease(repo, opts, fn lease ->
        ledger = read_versions(repo, "schema_migrations") || MapSet.new()

        module
        |> steps()
        |> Enum.reject(&MapSet.member?(ledger, &1.version))
        |> apply_versions(repo, lease)
        |> case do
          {:ok, applied} -> {:ok, %{applied: applied, pending_data: []}}
          error -> error
        end
      end)
    end
  end

  def baseline_sql do
    :dawarich |> Application.app_dir("priv/release_migrations/baseline.sql") |> File.read!()
  end

  defp preflight(repo) do
    with :ok <- Lease.require_two_connections(repo) do
      %{rows: [[timezone, schema, others]]} = repo.query!(@preflight_sql, [], log: false)
      ledger = read_versions(repo, "schema_migrations")

      cond do
        timezone != "UTC" ->
          {:error, {:timezone, timezone}}

        rails = rails_migrator(repo) ->
          {:error, {:rails_migrating, rails}}

        schema != "public" or others != [] ->
          {:error, {:foreign_schema, schema, others}}

        count = Ledger.not_dawarich(ledger) ->
          {:error, {:not_dawarich, count}}

        release = Ledger.below_floor(ledger) ->
          {:error, {:below_floor, release}}

        true ->
          :ok
      end
    end
  end

  defp rails_migrator(repo) do
    %{rows: [[database]]} = repo.query!("SELECT current_database()::text", [], log: false)
    key = @rails_migrator_salt * :erlang.crc32(database)

    %{rows: rows} =
      repo.query!(@rails_lock_sql, [div(key, 4_294_967_296), rem(key, 4_294_967_296)], log: false)

    case rows do
      [[pid] | _] -> pid
      [] -> nil
    end
  end

  defp run(repo, lease, releases, baseline, applied) do
    known = Enum.flat_map(releases, &ReleaseMigration.versions/1)

    case Ledger.classify(read_versions(repo, "schema_migrations"), known) do
      :fresh ->
        with :ok <- apply_baseline(repo, lease, baseline || baseline_sql()),
             do: run(repo, lease, releases, baseline, applied ++ ["baseline"])

      :current ->
        {:ok, %{applied: applied, pending_data: pending_data(repo, releases)}}

      {:pending, versions} ->
        by_version = releases |> Enum.flat_map(&steps/1) |> Map.new(&{&1.version, &1})

        case versions |> Enum.map(&Map.fetch!(by_version, &1)) |> apply_versions(repo, lease) do
          {:ok, done} ->
            {:ok, %{applied: applied ++ done, pending_data: pending_data(repo, releases)}}

          error ->
            error
        end

      refusal ->
        {:error, refusal}
    end
  end

  defp steps(module) do
    Enum.map(module.steps(), fn step ->
      {version, fun, transaction?} = ReleaseMigration.normalize(step)
      %{release: module.release(), version: version, fun: fun, transaction: transaction?}
    end)
  end

  defp apply_versions(steps, repo, lease) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, done} ->
      case apply_version(repo, lease, step) do
        :ok -> {:cont, {:ok, done ++ [step.version]}}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_version(repo, lease, step) do
    run_version(repo, lease, step)
  catch
    kind, reason -> failure(step.release, step.version, kind, reason, __STACKTRACE__)
  end

  defp run_version(repo, lease, %{transaction: true} = step) do
    repo.transaction(fn -> record(repo, lease, step, step.fun.(repo)) end)
    |> transaction_result()
  end

  defp run_version(repo, lease, step) do
    if rails = rails_migrator(repo) do
      {:error, {:rails_migrating, rails}}
    else
      result = step.fun.(repo)
      repo.transaction(fn -> record(repo, lease, step, result) end) |> transaction_result()
    end
  end

  defp failure(release, version, kind, reason, stacktrace),
    do: {:error, {:failed, release, version, Exception.format_banner(kind, reason, stacktrace)}}

  defp record(repo, lease, step, result) do
    fence!(repo, lease)

    repo.query!("INSERT INTO public.schema_migrations (version) VALUES ($1)", [step.version],
      log: false
    )

    for job <- step_jobs(result), do: insert_job!(repo, step.version, job)

    :ok
  end

  defp insert_job!(repo, version, {class, args, wait})
       when is_binary(class) and is_list(args) and is_integer(wait) and wait >= 0 do
    repo.query!(
      "INSERT INTO phoenix.release_migration_jobs (version, job_class, arguments, wait_seconds) VALUES ($1, $2, $3, $4)",
      [version, class, args, wait],
      log: false
    )
  end

  defp insert_job!(_repo, _version, job) do
    raise ArgumentError, "malformed job #{inspect(job)}; expected {class, args, wait_seconds}"
  end

  defp step_jobs({:jobs, jobs}), do: jobs
  defp step_jobs(_result), do: []

  defp transaction_result({:ok, :ok}), do: :ok
  defp transaction_result({:error, reason}), do: {:error, reason}

  defp apply_baseline(repo, lease, sql) do
    repo.transaction(fn ->
      ReleaseMigration.sql!(repo, sql)
      fence!(repo, lease)
      :ok
    end)
    |> transaction_result()
  catch
    kind, reason -> failure("baseline", nil, kind, reason, __STACKTRACE__)
  end

  defp fence!(repo, lease) do
    if rails = rails_migrator(repo), do: repo.rollback({:rails_migrating, rails})
    unless Lease.fenced?(repo, lease), do: repo.rollback({:lease_lost, lease.holder})
  end

  defp pending_data(repo, releases) do
    done = read_versions(repo, "data_migrations") || MapSet.new()
    releases |> Enum.flat_map(& &1.data_versions()) |> Enum.reject(&MapSet.member?(done, &1))
  end

  defp read_versions(repo, table) do
    %{rows: [[present]]} =
      repo.query!("SELECT to_regclass($1) IS NOT NULL", ["public.#{table}"], log: false)

    if present do
      %{rows: rows} = repo.query!("SELECT version FROM public.#{table}", [], log: false)
      MapSet.new(rows, fn [version] -> version end)
    end
  end
end
