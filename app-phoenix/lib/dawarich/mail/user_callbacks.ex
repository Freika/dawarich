defmodule Dawarich.Mail.UserCallbacks do
  @moduledoc false

  alias Dawarich.Imports.NativeOwnership
  alias Dawarich.Mail

  @workers %{
    "welcome" => Mail.WelcomeWorker,
    "explore_features" => Mail.ExploreFeaturesWorker,
    "archival_approaching" => Mail.ArchivalApproachingWorker,
    "oauth_account_link" => Mail.OauthAccountLinkWorker,
    "account_destroy_confirmation" => Mail.AccountDestroyConfirmationWorker
  }
  @retired ~w(trial_expired trial_expires_soon post_trial_reminder_early post_trial_reminder_late)

  def enqueue(repo, type, payload, opts \\ [])
  def enqueue(_repo, type, _payload, _opts) when type in @retired, do: :retired

  def enqueue(repo, type, payload, opts) do
    with {:ok, worker} <- worker(type),
         {:ok, args} <- worker.args_from_command(1, payload) do
      command = command(type)

      case repo.transaction(fn ->
             if NativeOwnership.lock(repo, "command:" <> command) == :oban do
               publish!(repo, command, worker, payload, args, opts)
             else
               :not_owner
             end
           end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp worker(type) do
    case Map.fetch(@workers, type) do
      {:ok, worker} -> {:ok, worker}
      :error -> {:error, :unknown_email_type}
    end
  end

  defp command("explore_features"), do: "users.explore_features_mail"
  defp command(type), do: "mail.user." <> type

  defp publish!(repo, command, worker, payload, args, opts) do
    event = Keyword.get_lazy(opts, :event_id, &Ecto.UUID.generate/0)
    at = Keyword.get_lazy(opts, :scheduled_at, &DateTime.utc_now/0)
    dedupe = if function_exported?(worker, :provider_key, 1), do: worker.provider_key(args)

    repo.query!(
      "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6,$7) ON CONFLICT DO NOTHING",
      [
        Ecto.UUID.dump!(event),
        command,
        payload,
        %{"producer" => "Phoenix user mail callback"},
        payload["user_id"],
        dedupe,
        at
      ],
      log: false
    )

    :ok
  end
end
