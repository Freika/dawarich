defmodule Dawarich.Release.Cloud do
  @moduledoc false
  alias Dawarich.{ReleaseMigrator, ReleaseMigrations}
  alias Dawarich.Release.{CloudPreflight, CloudJobs, Native}
  alias Dawarich.ReleaseMigrator.Lease

  def migrate(repo, opts) do
    safely(fn ->
      with {:ok, opts} <- CloudPreflight.check(repo, opts) do
        Dawarich.Cloud.SessionConnection.with_migration_lock(repo, opts, fn ->
          with {:ok, opts} <- CloudPreflight.check(repo, opts) do
            install_private(repo)
            Lease.with_lease(repo, opts, fn lease -> provision(repo, opts, lease) end)
          end
        end)
      end
    end)
  end

  defp provision(repo, opts, lease) do
    fence!(repo, lease)
    opts = Dawarich.Release.CloudDataLedger.baseline(repo, opts)

    with {:ok, result} <-
           ReleaseMigrator.migrate(repo, Keyword.merge(opts, lease: lease, job_mode: :enqueue)),
         :ok <- CloudJobs.reconcile(repo, lease) do
      Keyword.get(opts, :hook, fn _, _ -> :ok end).(:before_registration_copy, lease)

      copied =
        repo.transaction(fn ->
          fence!(repo, lease)

          with {:ok, _} <- ReleaseMigrations.V1_13_1.copy_registration_setting(repo, opts) do
            fence!(repo, lease)
            :ok
          else
            {:error, reason} -> repo.rollback(reason)
          end
        end)

      case copied do
        {:ok, :ok} ->
          cond do
            result.pending_data != [] -> {:error, {:pending_data, result.pending_data}}
            not CloudJobs.ready?(repo) -> {:error, :pending_release_jobs}
            true -> :ok
          end

        error ->
          error
      end
    end
  end

  def seed(repo, opts) do
    safely(fn ->
      with {:ok, opts} <- CloudPreflight.check(repo, opts),
           true <- ready?(repo, opts),
           true <-
             Code.ensure_loaded?(Dawarich.Users.CreationEffects) and
               function_exported?(Dawarich.Users.CreationEffects, :apply, 3) do
        Dawarich.Cloud.SessionConnection.with_migration_lock(repo, opts, fn ->
          if ready?(repo, opts) do
            Lease.with_lease(repo, opts, fn lease ->
              fence!(repo, lease)
              result = Dawarich.Seeds.run(repo, Keyword.put(opts, :lease, lease))
              fence!(repo, lease)
              result
            end)
          else
            {:error, :seeds_require_current}
          end
        end)
      else
        false -> {:error, :creation_effects_or_readiness_required}
        error -> error
      end
    end)
  end

  def ready?(repo, opts) do
    opts = Keyword.put(opts, :rails_lock_check, false)

    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    Dawarich.Cloud.Configuration.manager(env) == :ok and
      CloudPreflight.schemas_present?(repo) and private_current?(repo) and
      ReleaseMigrator.status(repo, opts) == {:ok, :current} and data_current?(repo, opts) and
      repo.query!("SELECT 1 FROM phoenix.registration_setting WHERE id=true", [], log: false).num_rows ==
        1 and CloudJobs.ready?(repo)
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  defp private_current?(repo) do
    Enum.all?(CloudPreflight.private_paths(), fn {schema, path} ->
      repo
      |> Ecto.Migrator.migrations(path,
        prefix: schema,
        skip_table_creation: true,
        migration_lock: false
      )
      |> Enum.all?(fn {state, _, name} -> state == :up and name != "** FILE NOT FOUND **" end)
    end)
  end

  defp data_current?(repo, opts), do: Dawarich.Release.CloudDataLedger.current?(repo, opts)

  defp install_private(repo) do
    for {schema, path} <- CloudPreflight.private_paths() do
      Ecto.Migrator.run(repo, path, :up, all: true, prefix: schema, log: false)
    end
  end

  defp fence!(repo, lease) do
    Native.fence!(repo, lease)
  rescue
    RuntimeError -> throw({:cloud_refusal, :lease_lost})
  end

  defp safely(fun) do
    case fun.() do
      {:error, {:lease_lost, _}} -> {:error, :lease_lost}
      {:error, {:locked, _}} -> {:error, :migration_lock_busy}
      {:error, {:failed, release, version, _}} -> {:error, {:migration_failed, release, version}}
      result -> result
    end
  rescue
    error in RuntimeError ->
      if error.message == Dawarich.CLI.Migrate.describe(:migration_lock_busy),
        do: {:error, :migration_lock_busy},
        else: {:error, :cloud_provisioning_refused}

    _ ->
      {:error, :cloud_provisioning_refused}
  catch
    :throw, {:cloud_refusal, reason} -> {:error, reason}
    _, _ -> {:error, :cloud_provisioning_refused}
  end
end
