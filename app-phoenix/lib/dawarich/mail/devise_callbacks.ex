defmodule Dawarich.Mail.DeviseCallbacks do
  @moduledoc false

  alias Dawarich.Mail.{DeviseNotificationWorker, ExploreFeatures}
  alias Dawarich.ReleaseMigration

  @load "SELECT email, encrypted_password, settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE"
  @fields [:email, :encrypted_password]

  def update(repo, id, changes, opts \\ []) when is_map(changes) do
    if Enum.any?(Map.keys(changes), &(&1 not in @fields)),
      do: raise(ArgumentError, "unsupported credential change")

    nested = repo.in_transaction?()

    result =
      repo.transaction(fn ->
        case repo.query!(@load, [id], log: false).rows do
          [[email, hash, settings]] ->
            before = %{id: id, email: email, encrypted_password: hash, settings: settings}
            after_user = Map.merge(before, changes)
            changed = Enum.filter(@fields, &(before[&1] != after_user[&1]))
            save!(repo, id, after_user, changed)
            jobs = after_update(before, after_user, opts)
            {after_user, jobs}

          [] ->
            repo.rollback(:missing)
        end
      end)

    case result do
      {:ok, {user, jobs}} ->
        if nested do
          {:ok, user}
        else
          case after_commit(jobs) do
            :ok -> {:ok, user}
            {:snooze, _} -> {:ok, user}
            {:error, reason} -> {:error, {:delivery, reason}}
          end
        end

      error ->
        error
    end
  end

  def after_commit(jobs) do
    Enum.reduce_while(jobs, :ok, fn job, :ok ->
      case DeviseNotificationWorker.perform(job) do
        :ok -> {:cont, :ok}
        {:snooze, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def after_update(before, after_user, opts \\ []) do
    env = Keyword.get_lazy(opts, :env, &System.get_env/0)

    if env["RAILS_ENV"] == "production" and not ReleaseMigration.self_hosted?(env) do
      locale = ExploreFeatures.locale(after_user.settings, Keyword.get(opts, :locale, "en"))

      for {field, kind, recipient} <- [
            {:email, "email_changed", before.email},
            {:encrypted_password, "password_change", after_user.email}
          ],
          before[field] != after_user[field],
          not Keyword.get(
            opts,
            if(kind == "email_changed", do: :skip_email_changed, else: :skip_password_change),
            false
          ) do
        args = %{
          "event_id" => Ecto.UUID.generate(),
          "user_id" => after_user.id,
          "kind" => kind,
          "recipient" => recipient,
          "resource_email" => after_user.email,
          "locale" => locale
        }

        Oban.insert!(Keyword.get(opts, :oban, Oban), DeviseNotificationWorker.new(args))
      end
    else
      []
    end
  end

  defp save!(_repo, _id, _user, []), do: :ok

  defp save!(repo, id, user, fields) do
    assignments =
      fields |> Enum.with_index(2) |> Enum.map_join(", ", fn {field, n} -> "#{field}=$#{n}" end)

    repo.query!(
      "UPDATE users SET " <>
        assignments <>
        ", reset_password_token=NULL, reset_password_sent_at=NULL, updated_at=now() WHERE id=$1",
      [id | Enum.map(fields, &user[&1])],
      log: false
    )
  end
end
