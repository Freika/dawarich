defmodule Dawarich.Mail.UserCallbacks do
  @moduledoc false

  alias Dawarich.Imports.NativeOwnership
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Mail
  alias Dawarich.ReleaseMigration

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

  def created(repo, user_id, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    repo.transaction(fn ->
      if not ReleaseMigration.self_hosted?(env) and not Keyword.get(opts, :skip_auto_trial, false) do
        lock_user!(repo, user_id)
        types = ["mail.user.welcome", "users.explore_features_mail"]
        ensure_native!(repo, types)
        now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
        payload = %{"user_id" => user_id, "locale" => Keyword.get(opts, :locale, "en")}
        publish!(repo, hd(types), payload, "welcome:#{user_id}", now)

        publish!(
          repo,
          List.last(types),
          payload,
          "explore-features:#{user_id}",
          Dawarich.Users.CreationEffects.calendar_days(repo, now, 2, env)
        )
      end

      :ok
    end)
  end

  def link(repo, action, user_id, url, opts \\ [])
      when action in ["oauth_account_link", "account_destroy_confirmation"] do
    token = url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("token")
    [_header, payload, _signature] = String.split(token, ".")

    expires =
      payload |> Base.url_decode64!(padding: false) |> Jason.decode!() |> Map.fetch!("exp")

    digest = :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
    type = "mail.user." <> action
    prefix = if action == "oauth_account_link", do: "oauth-link", else: "destroy-confirmation"

    body = %{
      "user_id" => user_id,
      "locale" => Keyword.get(opts, :locale, "en"),
      "link_url" => url,
      "link_token_sha256" => digest,
      "link_expires_at" => expires
    }

    body =
      if action == "oauth_account_link",
        do: Map.put(body, "provider_label", Keyword.fetch!(opts, :provider_label)),
        else: body

    repo.transaction(fn ->
      lock_user!(repo, user_id)
      ensure_native!(repo, [type])

      publish!(
        repo,
        type,
        body,
        "#{prefix}:#{user_id}:#{digest}",
        Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
      )

      :ok
    end)
  end

  defp lock_user!(repo, id) do
    case repo.query!("SELECT id FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE", [id],
           log: false
         ).rows do
      [[_]] -> :ok
      [] -> repo.rollback(:missing)
    end
  end

  defp ensure_native!(repo, types) do
    for type <- Enum.sort(types) do
      if Ownership.lock(repo, "command:" <> type) != :oban, do: repo.rollback(:mail_owner)
    end
  end

  defp publish!(repo, type, payload, key, at) do
    event = Dawarich.AfterCommit.identity(payload["user_id"], key)

    case Dawarich.AfterCommit.intent(repo, type, payload,
           event_id: event,
           dedupe_key: key,
           scheduled_at: at
         ) do
      :ok -> :ok
      {:error, reason} -> repo.rollback(reason)
    end
  end
end
