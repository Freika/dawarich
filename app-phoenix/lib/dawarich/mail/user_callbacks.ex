defmodule Dawarich.Mail.UserCallbacks do
  @moduledoc false

  alias Dawarich.Jobs.Ownership
  alias Dawarich.ReleaseMigration

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
          DateTime.add(now, 172_800)
        )
      end

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
    repo.query!(
      "INSERT INTO public.job_outbox(event_id,command_type,command_version,payload,aggregate_id,dedupe_key,scheduled_at,metadata) " <>
        "SELECT $1::uuid,$2::varchar,1,$3::jsonb,$4::bigint,$5::varchar,$6::timestamptz,$7::jsonb WHERE NOT EXISTS(SELECT 1 FROM public.job_outbox WHERE command_type=$2 AND dedupe_key=$5)",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        type,
        payload,
        payload["user_id"],
        key,
        at,
        %{"producer" => "Phoenix user callback"}
      ],
      log: false
    )
  end
end
