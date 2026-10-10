defmodule Dawarich.Admin.UserSecurity do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Settings
  alias Dawarich.Repo

  def reset(actor, id, context) do
    repo = Map.get(context, :repo, Repo)

    with :ok <- authorize(actor, repo, context),
         {:ok, _} <- target(repo, id) do
      case repo.transaction(fn ->
             with :ok <- authorize(actor, repo, context),
                  [[email]] <-
                    repo.query!(
                      "SELECT email FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
                      [id],
                      log: false
                    ).rows,
                  {:ok, %{notification: notification}} <-
                    Dawarich.Auth.Recovery.Lifecycle.request_reset(email, context) do
               enqueue =
                 Map.get(context, :enqueue, fn notification ->
                   Dawarich.Auth.Recovery.MailWorker.enqueue(
                     notification,
                     Map.get(context, :oban, Oban)
                   )
                 end)

               if enqueue.(notification) == :ok, do: {:ok, id}, else: repo.rollback(:mail)
             else
               [] -> {:handoff, :target}
               other -> other
             end
           end) do
        {:ok, outcome} -> outcome
        {:error, :mail} -> {:terminal, :mail}
      end
    end
  end

  def rotate(actor, id, context) do
    repo = Map.get(context, :repo, Repo)

    with :ok <- authorize(actor, repo, context),
         {:ok, settings} <- target(repo, id),
         {:ok, settings} <- sanitize(settings) do
      key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()

      result =
        repo.query!(
          "UPDATE users SET api_key=$1,settings=$2,updated_at=$3 WHERE id=$4",
          [key, settings, now, id],
          log: false
        )

      if result.num_rows == 1, do: {:ok, id}, else: {:terminal, :target}
    end
  end

  defp authorize(actor, repo, context) do
    cond do
      context[:self_hosted] != true ->
        {:handoff, :cloud}

      context[:oidc] == true ->
        {:handoff, :oidc}

      true ->
        case repo.query!(
               "SELECT admin FROM users WHERE id=$1 AND deleted_at IS NULL FOR SHARE",
               [actor.id],
               log: false
             ).rows do
          [[true]] -> :ok
          _ -> {:handoff, :actor}
        end
    end
  end

  defp target(repo, id) when is_integer(id) and id > 0 do
    case repo.query!("SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL", [id],
           log: false
         ).rows do
      [[settings]] -> {:ok, settings}
      _ -> {:handoff, :target}
    end
  end

  defp target(_, _), do: {:handoff, :target}

  defp sanitize(settings) do
    case Settings.sanitize(settings) do
      {:ok, value} -> {:ok, value}
      _ -> {:handoff, :settings_callback}
    end
  end
end
