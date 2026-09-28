defmodule Dawarich.Jobs.Ownership do
  @moduledoc false

  @owners [:sidekiq, :oban]

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
    case repo.query!("SELECT owner FROM phoenix.job_owners WHERE key = $1 FOR SHARE", [key],
           log: false
         ).rows do
      [["oban"]] -> :oban
      _ -> :sidekiq
    end
  end

  def put!(repo, key, owner, opts \\ []) when owner in @owners do
    repo.query!(
      """
      INSERT INTO phoenix.job_owners (key, owner, pinned, updated_at, updated_by)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (key) DO UPDATE SET owner = EXCLUDED.owner, pinned = EXCLUDED.pinned,
        updated_at = EXCLUDED.updated_at, updated_by = EXCLUDED.updated_by
      """,
      [
        key,
        Atom.to_string(owner),
        Keyword.get(opts, :pinned, false),
        DateTime.utc_now(),
        Keyword.get(opts, :by, "phoenix")
      ],
      log: false
    )

    :ok
  end
end
