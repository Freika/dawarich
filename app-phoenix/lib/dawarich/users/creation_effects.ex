defmodule Dawarich.Users.CreationEffects do
  @moduledoc false
  alias Dawarich.{AfterCommit, ReleaseMigration, UserTimeZone}
  alias Dawarich.Imports.ZonePeriod
  alias Dawarich.Jobs.Processed
  alias Dawarich.Users.WebhookCommands

  def apply(repo, user_id, opts \\ []) do
    if repo.in_transaction?() do
      case repo.query!(
             "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
             [user_id],
             log: false
           ).rows do
        [[settings]] -> complete(repo, user_id, settings, opts)
        [] -> {:error, :missing}
      end
    else
      {:error, :transaction_required}
    end
  end

  defp complete(repo, id, settings, opts) do
    event = Keyword.get(opts, :event_id, AfterCommit.identity(id, "users.creation_effects"))

    if Processed.done?(repo, event) do
      :ok
    else
      env = Keyword.get_lazy(opts, :env, &System.get_env/0)
      now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0) |> utc()
      opts = opts |> Keyword.put(:env, env) |> Keyword.put(:now, now)
      key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

      repo.query!(
        "UPDATE users SET api_key=COALESCE(NULLIF(api_key,''),$2) WHERE id=$1",
        [id, key],
        log: false
      )

      unless Keyword.get(opts, :skip_auto_trial, false) do
        if ReleaseMigration.self_hosted?(env) do
          Dawarich.Admin.UserPersistence.activate(repo, id, DateTime.to_naive(now), settings, env)
        else
          expiry = calendar_days(repo, now, 7, env)

          repo.query!(
            "UPDATE users SET status=2,active_until=$2,updated_at=$3 WHERE id=$1",
            [id, DateTime.to_naive(expiry), DateTime.to_naive(now)],
            log: false
          )

          case Dawarich.Mail.UserCallbacks.created(repo, id, opts) do
            {:ok, :ok} -> :ok
            {:error, reason} -> repo.rollback(reason)
          end
        end
      end

      unless ReleaseMigration.self_hosted?(env) do
        callback =
          Keyword.get(opts, :webhook, fn id ->
            WebhookCommands.creation(repo, id, AfterCommit.identity(id, "users.creation_webhook"),
              scheduled_at: now
            )
          end)

        case callback.(id) do
          :ok -> :ok
          {:error, reason} -> repo.rollback(reason)
          _ -> repo.rollback(:webhook_owner)
        end
      end

      Processed.mark!(repo, event, "users.creation_effects")
    end
  end

  def calendar_days(repo, now, days, env) do
    data = repo |> UserTimeZone.iana(%{}, env) |> ZonePeriod.load!()
    local = ZonePeriod.local_now(data, utc(now))
    future = NaiveDateTime.add(local, days * 86_400)
    result = data |> ZonePeriod.resolve(future) |> DateTime.from_unix!()
    %{result | microsecond: local.microsecond}
  end

  defp utc(%NaiveDateTime{} = now), do: DateTime.from_naive!(now, "Etc/UTC")
  defp utc(%DateTime{} = now), do: now
end
