defmodule Dawarich.Auth.TwoFactor.Secret do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Settings, Token}
  alias Dawarich.{Accounts, ActiveRecordEncryption, Repo}

  @variables ~w(OTP_ENCRYPTION_PRIMARY_KEY OTP_ENCRYPTION_DETERMINISTIC_KEY OTP_ENCRYPTION_KEY_DERIVATION_SALT)

  def available?(env \\ System.get_env()),
    do: Enum.all?(@variables, &(not Token.blank?(env[&1])))

  def key(env \\ System.get_env()) do
    if available?(env), do: ActiveRecordEncryption.key(env), else: {:handoff, :unavailable}
  end

  def decrypt(ciphertext, env \\ System.get_env()) do
    with {:ok, key} <- key(env) do
      case ciphertext && ActiveRecordEncryption.decrypt(ciphertext, key) do
        nil -> {:ok, nil}
        {:ok, clear} -> {:ok, clear}
        _ -> {:handoff, :encryption}
      end
    end
  end

  def encrypt(plaintext, env \\ System.get_env()) when is_binary(plaintext) do
    with {:ok, key} <- key(env), do: {:ok, ActiveRecordEncryption.encrypt(plaintext, key)}
  end

  def actor(id, salt, context) do
    cond do
      context[:self_hosted] != true -> {:handoff, :cloud}
      context[:oidc] == true -> {:handoff, :oidc}
      not is_integer(id) -> {:handoff, :actor}
      true -> find_actor(id, salt, context)
    end
  end

  defp find_actor(id, salt, context) do
    repo = Map.get(context, :repo, Repo)

    case repo.one(from(u in Account, where: u.id == ^id and is_nil(u.deleted_at)), log: false) do
      nil ->
        {:handoff, :actor}

      user ->
        [[settings]] =
          repo.query!("SELECT settings FROM users WHERE id=$1", [id], log: false).rows

        support(%{user | settings: settings}, salt, context)
    end
  end

  defp support(user, salt, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    hash = user.encrypted_password

    cond do
      not is_binary(hash) or not Regex.match?(~r/\A\$2[ab]\$\d{2}\$[.\/A-Za-z0-9]{53}\z/, hash) ->
        {:handoff, :actor}

      not is_binary(salt) or not Plug.Crypto.secure_compare(binary_part(hash, 0, 29), salt) ->
        {:handoff, :session}

      not Accounts.unlocked?(user, now) ->
        {:handoff, :locked}

      not Token.blank?(user.provider) ->
        {:handoff, :provider}

      user.status == 3 ->
        {:handoff, :payment}

      not valid_email?(user.email) ->
        {:handoff, :validation}

      not is_map(user.settings) or Settings.sanitize(user.settings) != {:ok, user.settings} ->
        {:handoff, :settings_callback}

      true ->
        {:ok, user}
    end
  end

  defp valid_email?(email) when is_binary(email) do
    email == Account.normalize_email(email) and Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/u, email)
  end

  defp valid_email?(_), do: false
end
