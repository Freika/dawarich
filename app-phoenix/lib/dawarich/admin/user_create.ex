defmodule Dawarich.Admin.UserCreate do
  @moduledoc false
  alias Dawarich.Admin.{UserPersistence, UserValidation}
  alias Dawarich.Auth.Account
  alias Dawarich.Repo
  @rounds if(Mix.env() == :test, do: 4, else: 12)

  def call(actor, params, context) do
    repo = Map.get(context, :repo, Repo)

    with :ok <- authorize(actor, repo, context),
         {:ok, changes} <-
           UserValidation.create(params, validation_context(params, repo, context)) do
      create(changes, repo, Map.put(context, :settings, Dawarich.UserSettings.get(actor)))
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

  defp validation_context(params, repo, context) do
    email = Account.normalize_email(params["email"] || "")

    [[taken]] =
      repo.query!("SELECT EXISTS(SELECT 1 FROM users WHERE email=$1)", [email], log: false).rows

    Map.put(context, :email_taken, taken)
  end

  defp create(changes, repo, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()
    bytes = binary_part(changes.password, 0, min(byte_size(changes.password), 72))
    hash = Bcrypt.hash_pwd_salt(bytes, log_rounds: @rounds)

    case UserPersistence.insert(repo, changes.email, hash, now) do
      {:ok, id} ->
        UserPersistence.activate(
          repo,
          id,
          now,
          context.settings,
          Map.get(context, :env, System.get_env())
        )

      {:error, :unique} ->
        {:terminal, :unique}
    end
  end
end
