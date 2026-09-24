defmodule Dawarich.ReleaseMigrator.Lease do
  @moduledoc false

  @name "release_migrator"

  def require_two_connections(repo) do
    dynamic = repo.get_dynamic_repo()

    {:ok, second} =
      repo.transaction(fn ->
        fn ->
          repo.put_dynamic_repo(dynamic)
          round_trip(repo)
        end
        |> Task.async()
        |> Task.await(:infinity)
      end)

    case second do
      {:error, %DBConnection.ConnectionError{reason: :queue_timeout}} -> {:error, :pool_too_small}
      other -> other
    end
  end

  def with_lease(repo, opts, fun) do
    lease = %{
      holder: Keyword.get_lazy(opts, :holder, &holder/0),
      ttl_seconds: Keyword.get(opts, :lease_ttl_ms, 60_000) / 1000
    }

    deadline = System.monotonic_time(:millisecond) + Keyword.get(opts, :lease_wait_ms, 900_000)

    case acquire(repo, lease, deadline, Keyword.get(opts, :lease_poll_ms, 2_000)) do
      :ok ->
        dynamic = repo.get_dynamic_repo()
        renew_ms = Keyword.get(opts, :lease_renew_ms, 20_000)

        renewer =
          spawn_link(fn ->
            repo.put_dynamic_repo(dynamic)
            renew(repo, lease, renew_ms)
          end)

        try do
          fun.(lease)
        after
          Process.unlink(renewer)
          Process.exit(renewer, :kill)

          repo.query!(
            "DELETE FROM phoenix.release_migrator_leases WHERE name = $1 AND holder = $2",
            [@name, lease.holder],
            log: false
          )
        end

      {:error, _} = error ->
        error
    end
  end

  def fenced?(repo, lease, timeout \\ :infinity) do
    %{num_rows: rows} =
      repo.query!(
        "UPDATE phoenix.release_migrator_leases SET expires_at = clock_timestamp() + make_interval(secs => $3) WHERE name = $1 AND holder = $2",
        [@name, lease.holder, lease.ttl_seconds],
        log: false,
        timeout: timeout
      )

    rows == 1
  end

  defp acquire(repo, lease, deadline, poll_ms) do
    %{num_rows: taken} =
      repo.query!(
        """
        INSERT INTO phoenix.release_migrator_leases (name, holder, expires_at)
        VALUES ($1, $2, clock_timestamp() + make_interval(secs => $3))
        ON CONFLICT (name) DO UPDATE SET holder = EXCLUDED.holder, expires_at = EXCLUDED.expires_at
        WHERE phoenix.release_migrator_leases.expires_at < clock_timestamp()
           OR phoenix.release_migrator_leases.holder = EXCLUDED.holder
        """,
        [@name, lease.holder, lease.ttl_seconds],
        log: false
      )

    cond do
      taken == 1 ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        {:error, {:locked, current_holder(repo)}}

      true ->
        Process.sleep(poll_ms)
        acquire(repo, lease, deadline, poll_ms)
    end
  end

  defp renew(repo, lease, renew_ms) do
    Process.sleep(renew_ms)
    unless fenced?(repo, lease, renew_ms), do: exit(:lease_lost)
    renew(repo, lease, renew_ms)
  end

  defp current_holder(repo) do
    case repo.query!(
           "SELECT holder FROM phoenix.release_migrator_leases WHERE name = $1",
           [@name],
           log: false
         ) do
      %{rows: [[holder]]} -> holder
      _ -> nil
    end
  end

  defp round_trip(repo) do
    repo.transaction(fn -> repo.query!("SELECT 1", [], log: false) end, timeout: 5_000)
    :ok
  rescue
    error -> {:error, error}
  end

  defp holder do
    {:ok, host} = :inet.gethostname()
    "#{host}:#{System.pid()}:#{System.unique_integer([:positive])}"
  end
end
