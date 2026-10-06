defmodule Dawarich.Auth.TwoFactor.ApiActor do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Settings, Token}
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Secret, Totp}
  alias Dawarich.Repo

  def load(id, context) do
    cond do
      context[:self_hosted] != true and context[:native] != true -> {:replay, :cloud}
      context[:oidc] == true and context[:native] != true -> {:replay, :oidc}
      not is_integer(id) -> {:replay, :actor}
      true -> find(id, context)
    end
  end

  def password_valid?(user, password) when is_binary(password) do
    not Token.blank?(password) and
      Bcrypt.verify_pass(
        binary_part(password, 0, min(byte_size(password), 72)),
        user.encrypted_password
      )
  end

  def password_valid?(_, _), do: false

  defp find(id, context) do
    repo = Map.get(context, :repo, Repo)

    query = from(u in Account, where: u.id == ^id and is_nil(u.deleted_at))
    query = if context[:native], do: from(u in query, lock: "FOR UPDATE"), else: query

    case repo.one(query, log: false) do
      nil ->
        {:replay, :actor}

      user ->
        [[settings]] =
          repo.query!("SELECT settings FROM users WHERE id=$1", [id], log: false).rows

        support(%{user | settings: settings}, context)
    end
  end

  defp support(user, context) do
    cond do
      not is_binary(user.encrypted_password) or
          not Regex.match?(~r/\A\$2[ab]\$\d{2}\$[.\/A-Za-z0-9]{53}\z/, user.encrypted_password) ->
        {:replay, :password_state}

      not Token.blank?(user.provider) ->
        {:replay, :provider}

      not valid_email?(user.email) ->
        {:replay, :validation}

      not is_map(user.settings) or Settings.sanitize(user.settings) != {:ok, user.settings} ->
        {:replay, :settings_callback}

      not BackupCodes.supported?(user.otp_backup_codes) ->
        {:replay, :backup_state}

      true ->
        readable(user, context)
    end
  end

  defp readable(user, context) do
    case Secret.decrypt(user.otp_secret, Map.get_lazy(context, :env, &System.get_env/0)) do
      {:ok, nil} ->
        {:ok, user}

      {:ok, secret} ->
        Totp.decode(secret)
        {:ok, user}

      _ ->
        {:replay, :encryption}
    end
  rescue
    ArgumentError -> {:replay, :secret}
  end

  defp valid_email?(email) when is_binary(email),
    do: email == Account.normalize_email(email) and Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/u, email)

  defp valid_email?(_), do: false
end
