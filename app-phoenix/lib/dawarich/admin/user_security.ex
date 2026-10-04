defmodule Dawarich.Admin.UserSecurity do
  @moduledoc false
  alias Dawarich.Auth.Recovery.Settings
  alias Dawarich.Repo

  def reset(_actor, _id, _context), do: {:handoff, :synchronous_mail}

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
        case repo.query!("SELECT admin FROM users WHERE id=$1 AND deleted_at IS NULL", [actor.id],
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
