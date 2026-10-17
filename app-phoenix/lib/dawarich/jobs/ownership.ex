defmodule Dawarich.Jobs.Ownership do
  @moduledoc false

  @owners [:sidekiq, :oban]
  @joint_keys ~w(command:mail.user.archival_approaching cron:lite_archival_warning_job)

  def joint_keys(key), do: if(key in @joint_keys, do: @joint_keys, else: [key])

  def ensure_rows!(repo, keys) do
    for key <- Enum.sort(keys) do
      repo.query!(
        "INSERT INTO phoenix.job_owners (key) VALUES ($1) ON CONFLICT (key) DO NOTHING",
        [key],
        log: false
      )
    end
  end

  def with_owner(repo, key, runtime, fun) when runtime in @owners and is_function(fun, 0) do
    result =
      repo.transaction(fn ->
        case lock(repo, key) do
          ^runtime -> {:ok, fun.()}
          owner -> {:skip, owner}
        end
      end)

    case result do
      {:ok, outcome} -> outcome
      {:error, reason} -> {:error, reason}
    end
  end

  def lock(repo, key) do
    keys = joint_keys(key)
    ensure_rows!(repo, keys)

    owners =
      repo.query!(
        "SELECT key, owner FROM phoenix.job_owners WHERE key = ANY($1) ORDER BY key FOR SHARE",
        [keys],
        log: false
      ).rows

    case owners |> Enum.map(&List.last/1) |> Enum.uniq() do
      ["oban"] -> :oban
      ["sidekiq"] -> :sidekiq
      _ -> :inconsistent
    end
  end

  def put!(repo, key, owner, opts \\ []) when owner in @owners do
    {:ok, :ok} =
      repo.transaction(fn ->
        repo.query!("SET LOCAL lock_timeout = '2s'", [], log: false)
        keys = joint_keys(key)
        ensure_rows!(repo, keys)

        repo.query!(
          "SELECT key FROM phoenix.job_owners WHERE key = ANY($1) ORDER BY key FOR UPDATE",
          [keys],
          log: false
        )

        repo.query!(
          "UPDATE phoenix.job_owners SET owner = $2, pinned = $3, updated_at = $4, updated_by = $5 WHERE key = ANY($1)",
          [
            keys,
            Atom.to_string(owner),
            Keyword.get(opts, :pinned, false),
            DateTime.utc_now(),
            Keyword.get(opts, :by, "phoenix")
          ],
          log: false
        )

        :ok
      end)

    :ok
  end
end
