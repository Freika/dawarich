defmodule Dawarich.Auth.AccountClosure do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Auth.{Account, AccountValidation}
  alias Dawarich.Auth.Recovery.{Settings, Token}

  def actor(id, salt, context) when is_integer(id) and is_binary(salt) do
    repo = Map.get(context, :repo, Repo)

    case repo.one(from(u in Account, where: u.id == ^id and is_nil(u.deleted_at)), log: false) do
      nil ->
        {:handoff, :actor}

      user ->
        now = Map.get(context, :clock, &DateTime.utc_now/0).()
        hash = user.encrypted_password

        cond do
          not is_binary(hash) or byte_size(hash) < 29 -> {:handoff, :actor}
          not Plug.Crypto.secure_compare(binary_part(hash, 0, 29), salt) -> {:handoff, :session}
          not Accounts.unlocked?(user, now) -> {:handoff, :locked}
          true -> {:ok, user}
        end
    end
  end

  def actor(_, _, _), do: {:handoff, :actor}

  def update(id, salt, params, context) do
    repo = Map.get(context, :repo, Repo)

    {:ok, result} =
      repo.transaction(fn ->
        repo.one(from(u in Account, where: u.id == ^id, lock: "FOR UPDATE"), log: false)

        with {:ok, user} <- actor(id, salt, context) do
          email = Account.normalize_email(params["email"] || user.email)

          taken =
            repo.exists?(
              from(u in Account,
                where: u.email == ^email and u.id != ^id and is_nil(u.deleted_at)
              ),
              log: false
            )

          provider = not Token.blank?(user.provider)
          valid = provider or password_valid?(params["current_password"], user.encrypted_password)

          result =
            AccountValidation.validate(params, user.email,
              current_password_valid: valid,
              email_taken: taken,
              locale: Map.get(context, :locale, "en")
            )

          if result.errors != [],
            do: {:error, result.render},
            else: save(repo, user, result.changes, context)
        end
      end)

    result
  end

  defp save(repo, user, changes, context) do
    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows

    with {:ok, settings} <- Settings.sanitize(settings) do
      {password, changes} = Map.pop(changes, :password)

      changes =
        if password do
          hash =
            Bcrypt.hash_pwd_salt(binary_part(password, 0, min(byte_size(password), 72)),
              log_rounds: Map.get(context, :log_rounds, 12)
            )

          Map.merge(changes, %{
            encrypted_password: hash,
            reset_password_token: nil,
            reset_password_sent_at: nil
          })
        else
          changes
        end

      changes =
        changes
        |> Map.put(:settings, settings)
        |> Map.put(:updated_at, Map.get(context, :clock, &DateTime.utc_now/0).())

      case repo.update(
             Ecto.Changeset.change(user, changes)
             |> Ecto.Changeset.unique_constraint(:email, name: :index_users_on_email),
             log: false,
             mode: :savepoint
           ) do
        {:ok, user} ->
          {:ok, user}

        {:error, _} ->
          {:error, %{email: user.email, errors: [{:email, :taken, %{}}], messages: []}}
      end
    else
      _ -> {:handoff, :settings_callback}
    end
  end

  defp password_valid?(password, hash) when is_binary(password),
    do:
      not Token.blank?(password) and
        Bcrypt.verify_pass(binary_part(password, 0, min(byte_size(password), 72)), hash)

  defp password_valid?(_, _), do: false
end
