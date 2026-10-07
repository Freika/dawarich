defmodule Dawarich.AfterCommit.Callback do
  @moduledoc false
  alias Dawarich.Jobs.Processed

  def run(repo, event_id, handler, effect) do
    if repo.in_transaction?() do
      {:error, :transaction_required}
    else
      repo.checkout(fn ->
        repo.query!("SELECT pg_advisory_lock(hashtextextended($1,0))", [event_id], log: false)

        try do
          if Processed.done?(repo, event_id) do
            :ok
          else
            case effect.() do
              :ok -> Processed.mark!(repo, event_id, handler)
              {:error, _} = error -> error
              _ -> {:error, :callback_failed}
            end
          end
        after
          repo.query!("SELECT pg_advisory_unlock(hashtextextended($1,0))", [event_id], log: false)
        end
      end)
    end
  rescue
    _ -> {:error, :callback_failed}
  catch
    :exit, _ -> {:error, :callback_failed}
  end
end
