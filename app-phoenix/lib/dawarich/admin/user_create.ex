defmodule Dawarich.Admin.UserCreate do
  @moduledoc false
  alias Dawarich.Admin.UserValidation
  alias Dawarich.Auth.Account
  alias Dawarich.{Repo, UserTimeZone}
  @rounds if(Mix.env() == :test, do: 4, else: 12)

  def call(actor, params, context) do
    repo = Map.get(context, :repo, Repo)

    with :ok <- authorize(actor, repo, context),
         {:ok, changes} <-
           UserValidation.create(params, validation_context(params, repo, context)) do
      create(changes, repo, Map.put(context, :settings, actor.settings))
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

    result =
      repo.transaction(fn ->
        case repo.query!(
               "INSERT INTO users(email,encrypted_password,created_at,updated_at) VALUES($1,$2,$3,$3) ON CONFLICT(email) DO NOTHING RETURNING id",
               [changes.email, hash, now],
               log: false
             ).rows do
          [[id]] ->
            key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
            repo.query!("UPDATE users SET api_key=$1 WHERE id=$2", [key, id], log: false)
            id

          [] ->
            repo.rollback(:unique)
        end
      end)

    case result do
      {:ok, id} -> activate(repo, id, now, context)
      {:error, :unique} -> {:terminal, :unique}
    end
  end

  defp activate(repo, id, now, context) do
    zone = UserTimeZone.iana(repo, context.settings, Map.get(context, :env, System.get_env()))

    repo.query!(
      "UPDATE users SET status=1,plan=1,active_until=((($1::timestamp AT TIME ZONE 'UTC') AT TIME ZONE $2)+interval '1000 years') AT TIME ZONE $2 AT TIME ZONE 'UTC',updated_at=$1 WHERE id=$3",
      [now, zone, id],
      log: false
    )

    {:ok, id}
  end
end
