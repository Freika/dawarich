defmodule Dawarich.Auth.AccountDestroy do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.{Account, DestroyToken}
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.{RailsCache.Wire, Redis, Repo}

  def request(id, params, context) do
    transaction(context, fn repo ->
      with {:ok, user} <- actor(repo, id),
           :ok <- family_guard(repo, id) do
        if Map.get(context, :self_hosted, true) do
          if confirmed?(user, params),
            do: schedule(repo, user, context),
            else: {:error, :password_required}
        else
          request_confirmation(user, context)
        end
      end
    end)
  end

  def request_as_admin(actor_id, id, context) do
    transaction(context, fn repo ->
      with true <- context[:self_hosted] == true and context[:oidc] != true,
           [[true]] <-
             repo.query!(
               "SELECT admin FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
               [actor_id],
               log: false
             ).rows,
           {:ok, user} <- actor(repo, id),
           :ok <- family_guard(repo, id) do
        schedule(repo, user, context)
      else
        false -> {:error, :actor}
        [] -> {:error, :actor}
        [[false]] -> {:error, :actor}
        other -> other
      end
    end)
  end

  def confirm(token, context) do
    with {:ok, claims} <- DestroyToken.verify(token, context),
         :ok <- worker_ready(context),
         true <- DestroyToken.consume(claims["jti"], context) do
      confirm_reserved(claims, context)
    else
      false -> {:error, :replayed}
      other -> other
    end
  end

  defp confirm_reserved(claims, context) do
    result =
      transaction(context, fn repo ->
        with {:ok, user} <- actor(repo, claims["user_id"]),
             :ok <- family_guard(repo, user.id) do
          schedule(repo, user, context)
        end
      end)

    case result do
      {:ok, :scheduled} -> :ok
      _ -> DestroyToken.release(claims["jti"], context)
    end

    result
  catch
    kind, reason ->
      DestroyToken.release(claims["jti"], context)
      :erlang.raise(kind, reason, __STACKTRACE__)
  end

  defp worker_ready(context) do
    if is_function(context[:enqueue_destroy], 1), do: :ok, else: {:error, :worker_owner}
  end

  defp schedule(repo, user, context) do
    case context[:enqueue_destroy] do
      enqueue when is_function(enqueue, 1) ->
        now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_naive()

        case repo.query!(
               "UPDATE users SET deleted_at=$2 WHERE id=$1 AND deleted_at IS NULL RETURNING id",
               [user.id, now],
               log: false
             ).rows do
          [] ->
            {:ok, :scheduled}

          [[id]] ->
            if enqueue.(id) == :ok, do: {:ok, :scheduled}, else: {:error, :worker_owner}
        end

      _ ->
        {:error, :worker_owner}
    end
  end

  defp request_confirmation(user, context) do
    case context[:enqueue_confirmation] do
      enqueue when is_function(enqueue, 1) ->
        now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
        bytes = Wire.encode_boolean(true, expires_at: now + 3600)
        command = Map.get(context, :cache_command, &Redis.cache_command/1)

        case command.([
               "SET",
               "account_destroy:rate_limit:#{user.id}",
               bytes,
               "NX",
               "PX",
               "3600000"
             ]) do
          {:ok, "OK"} ->
            with {:ok, token} <- DestroyToken.issue(user.id, context) do
              url =
                context.base_url <>
                  "/users/me/destroy/confirm?" <> URI.encode_query(%{"token" => token})

              payload = %{
                "user_id" => user.id,
                "locale" => Map.get(context, :locale, "en"),
                "link_url" => url,
                "link_token_sha256" => Base.encode16(:crypto.hash(:sha256, token), case: :lower),
                "link_expires_at" => now + 3600
              }

              if enqueue.(payload) == :ok, do: {:ok, :sent}, else: {:error, :mail_owner}
            end

          {:ok, nil} ->
            {:error, :rate_limited}

          _ ->
            {:error, :cache}
        end

      _ ->
        {:error, :mail_owner}
    end
  end

  defp confirmed?(user, params) do
    password = params["password"]

    valid =
      is_binary(password) and not Token.blank?(password) and user.encrypted_password != "" and
        Bcrypt.verify_pass(
          binary_part(password, 0, min(byte_size(password), 72)),
          user.encrypted_password
        )

    valid or
      (not Token.blank?(user.provider) and is_binary(params["confirm_email"]) and
         Account.normalize_email(params["confirm_email"]) == Account.normalize_email(user.email))
  end

  defp actor(repo, id) do
    case repo.one(
           from(u in Account, where: u.id == ^id and is_nil(u.deleted_at), lock: "FOR UPDATE"),
           log: false
         ) do
      nil -> {:error, :actor}
      user -> {:ok, user}
    end
  end

  defp family_guard(repo, id) do
    case repo.query!(
           "SELECT f.id FROM families f JOIN family_memberships m ON m.family_id=f.id WHERE m.user_id=$1 AND m.role=0 FOR UPDATE OF f",
           [id],
           log: false
         ).rows do
      [] ->
        :ok

      [[family]] ->
        [[count]] =
          repo.query!("SELECT count(*) FROM family_memberships WHERE family_id=$1", [family],
            log: false
          ).rows

        if count <= 1, do: :ok, else: {:error, :cannot_delete_account}
    end
  end

  defp transaction(context, fun) do
    repo = Map.get(context, :repo, Repo)

    case repo.transaction(fn ->
           case fun.(repo) do
             {:error, reason} -> repo.rollback(reason)
             result -> result
           end
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end
end
