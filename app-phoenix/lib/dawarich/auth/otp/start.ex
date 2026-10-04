defmodule Dawarich.Auth.Otp.Start do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Otp.Pending
  alias Dawarich.Auth.Recovery.{Settings, Token}
  alias Dawarich.Auth.TwoFactor.Secret
  alias Dawarich.Repo

  def candidate?(email, context) when is_binary(email) do
    emails = Enum.uniq([email, Account.normalize_email(email)])

    query =
      from(u in Account,
        where: u.email in ^emails and u.otp_required_for_login == true,
        select: u.id,
        limit: 1
      )

    not is_nil(Map.get(context, :repo, Repo).one(query, log: false))
  end

  def candidate?(_, _), do: false

  def prepare(email, password, session, context) when is_binary(email) do
    repo = Map.get(context, :repo, Repo)
    query = from(u in Account, where: u.email == ^email and is_nil(u.deleted_at))

    case repo.one(query, log: false) do
      nil -> ambiguous(email, repo)
      %{otp_required_for_login: false} -> :ordinary
      user -> challenge(user, password, session, context)
    end
  end

  def prepare(_, _, _, _), do: {:handoff, :parameters}

  def actor(id, context) when is_integer(id) do
    repo = Map.get(context, :repo, Repo)

    case repo.one(from(u in Account, where: u.id == ^id), log: false) do
      nil -> :missing
      user -> support(user, context)
    end
  end

  defp challenge(user, password, session, context) do
    with {:ok, user} <- support(user, context),
         true <- valid_password?(password, user.encrypted_password) do
      now = Map.get(context, :clock, &DateTime.utc_now/0).() |> DateTime.to_unix()
      {:challenge, user, Pending.start(session, user.id, context[:remember], now)}
    else
      false -> {:handoff, :password}
      other -> other
    end
  end

  defp ambiguous(email, repo) do
    normalized = Account.normalize_email(email)

    query =
      from(u in Account,
        where: u.email == ^normalized and u.otp_required_for_login == true,
        select: u.id,
        limit: 1
      )

    if repo.one(query, log: false), do: {:handoff, :ambiguous_otp}, else: :ordinary
  end

  defp support(user, context) do
    repo = Map.get(context, :repo, Repo)

    [[settings]] =
      repo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows

    user = %{user | settings: settings}
    env = Map.get_lazy(context, :env, &System.get_env/0)

    cond do
      context[:self_hosted] != true ->
        {:handoff, :cloud}

      context[:oidc] == true ->
        {:handoff, :oidc}

      not Secret.available?(env) ->
        {:handoff, :unavailable}

      user.otp_required_for_login != true ->
        {:handoff, :changed_account}

      not is_nil(user.deleted_at) ->
        {:handoff, :deleted}

      not is_nil(user.locked_at) ->
        {:handoff, :locked}

      not Token.blank?(user.provider) ->
        {:handoff, :provider}

      user.status == 3 ->
        {:handoff, :payment}

      not valid_hash?(user.encrypted_password) ->
        {:handoff, :password_state}

      not valid_email?(user.email) ->
        {:handoff, :email_state}

      not is_map(settings) or Settings.sanitize(settings) != {:ok, settings} ->
        {:handoff, :settings_callback}

      true ->
        {:ok, user}
    end
  end

  defp valid_hash?(hash) when is_binary(hash),
    do: Regex.match?(~r/\A\$2[ab]\$\d{2}\$[.\/A-Za-z0-9]{53}\z/, hash)

  defp valid_hash?(_), do: false

  defp valid_email?(email) when is_binary(email),
    do: email == Account.normalize_email(email) and Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/u, email)

  defp valid_email?(_), do: false

  defp valid_password?(password, hash) when is_binary(password) do
    not Token.blank?(password) and not String.contains?(password, <<0>>) and
      Bcrypt.verify_pass(binary_part(password, 0, min(byte_size(password), 72)), hash)
  end

  defp valid_password?(_, _), do: false
end
