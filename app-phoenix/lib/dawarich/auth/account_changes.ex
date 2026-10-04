defmodule Dawarich.Auth.AccountChanges do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.{Account, AccountValidation}
  alias Dawarich.Auth.Recovery.{Settings, Token}
  alias Dawarich.{Accounts, Repo}
  @rounds if(Mix.env() == :test, do: 4, else: 12)

  def update(id, session_salt, params, context \\ %{})

  def update(id, session_salt, params, context) when is_map(params) do
    with {:ok, user} <- actor(id, session_salt, context) do
      valid = valid_password?(params["current_password"], user.encrypted_password)

      result =
        AccountValidation.validate(params, user.email,
          current_password_valid: valid,
          email_taken: email_taken?(user, params, context),
          locale: Map.get(context, :locale, "en")
        )

      if result.errors == [],
        do: persist(user, credentials(result.changes, context), context),
        else: {:error, result.render}
    end
  end

  def update(_, _, _, _), do: {:handoff, :parameters}

  defp credentials(changes, context) do
    case Map.pop(changes, :password) do
      {nil, changes} ->
        changes

      {password, changes} ->
        bytes = binary_part(password, 0, min(byte_size(password), 72))
        rounds = max(4, Map.get(context, :log_rounds, @rounds))
        Map.put(changes, :encrypted_password, Bcrypt.hash_pwd_salt(bytes, log_rounds: rounds))
    end
  end

  defp email_taken?(user, params, context) do
    email = Account.normalize_email(Map.get(params, "email", user.email))
    repo = Map.get(context, :repo, Repo)
    repo.exists?(from u in Account, where: u.email == ^email and u.id != ^user.id)
  end

  defp persist(user, changes, _context) when map_size(changes) == 0, do: {:ok, user}

  defp persist(user, changes, context) do
    changes =
      Map.merge(changes, %{
        reset_password_token: nil,
        reset_password_sent_at: nil,
        updated_at: Map.get(context, :clock, &DateTime.utc_now/0).()
      })

    changeset =
      user
      |> Ecto.Changeset.change(changes)
      |> Ecto.Changeset.unique_constraint(:email, name: :index_users_on_email)

    {:ok, Map.get(context, :repo, Repo).update!(changeset, log: false)}
  end

  def actor(id, session_salt, context) do
    cond do
      context[:self_hosted] != true -> {:handoff, :cloud}
      context[:oidc] == true -> {:handoff, :oidc}
      not is_integer(id) -> {:handoff, :actor}
      true -> find_actor(id, session_salt, context)
    end
  end

  defp find_actor(id, session_salt, context) do
    repo = Map.get(context, :repo, Repo)

    case repo.one(from u in Account, where: u.id == ^id and is_nil(u.deleted_at)) do
      nil ->
        {:handoff, :actor}

      user ->
        [[settings]] =
          repo.query!("SELECT settings FROM users WHERE id=$1", [id], log: false).rows

        support(%{user | settings: settings}, session_salt, context)
    end
  end

  defp support(user, session_salt, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    hash = user.encrypted_password

    cond do
      not is_binary(hash) or byte_size(hash) < 29 ->
        {:handoff, :actor}

      not is_binary(session_salt) ->
        {:handoff, :session}

      not Plug.Crypto.secure_compare(binary_part(hash, 0, 29), session_salt) ->
        {:handoff, :session}

      not Accounts.unlocked?(user, now) ->
        {:handoff, :locked}

      not Token.blank?(user.provider) ->
        {:handoff, :provider}

      user.otp_required_for_login ->
        {:handoff, :otp}

      user.status == 3 ->
        {:handoff, :payment}

      Settings.sanitize(user.settings) != {:ok, user.settings} ->
        {:handoff, :settings_callback}

      true ->
        {:ok, user}
    end
  end

  defp valid_password?(password, hash) when is_binary(password) do
    not Token.blank?(password) and
      Bcrypt.verify_pass(binary_part(password, 0, min(byte_size(password), 72)), hash)
  end

  defp valid_password?(_, _), do: false
end
