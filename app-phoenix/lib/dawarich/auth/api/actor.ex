defmodule Dawarich.Auth.Api.Actor do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Settings, Token}
  alias Dawarich.Auth.Api.{BcryptWork, Payload}
  alias Dawarich.Repo

  def load(id, context) when is_integer(id), do: find(:id, id, context)
  def load(_, _), do: {:replay, :actor}
  def by_email(email, context) when is_binary(email), do: find(:email, email, context)
  def by_email(_, _), do: {:replay, :actor}
  def for_password(email, context), do: find(:email, email, context, true)
  def for_challenge(id, context), do: find(:id, id, context, true)

  defp find(column, value, context, include_rejected \\ false) do
    if context[:self_hosted] == true and context[:oidc] != true do
      repo = Map.get(context, :repo, Repo)
      query = from(u in Account, where: field(u, ^column) == ^value and is_nil(u.deleted_at))

      case repo.one(query, log: false) do
        nil ->
          {:replay, :actor}

        user ->
          [[settings]] =
            repo.query!("SELECT settings FROM users WHERE id=$1", [user.id], log: false).rows

          user = %{user | settings: Dawarich.UserSettings.provided(settings)}

          case support(user) do
            {:replay, reason} when include_rejected -> {:replay, reason, user}
            result -> result
          end
      end
    else
      {:replay, :context}
    end
  rescue
    _ in [Postgrex.Error, Ecto.QueryError, ArgumentError] -> {:replay, :actor_state}
  end

  defp support(user) do
    cond do
      Token.blank?(user.encrypted_password) ->
        {:replay, :blank_password_state}

      BcryptWork.classify(user.encrypted_password) == :invalid ->
        {:replay, :invalid_password_state}

      BcryptWork.classify(user.encrypted_password) == :uncomputable ->
        {:replay, :uncomputable_password_state}

      not is_binary(user.encrypted_password) or
          not Regex.match?(~r/\A\$2[ab]\$\d{2}\$[.\/A-Za-z0-9]{53}\z/, user.encrypted_password) ->
        {:replay, :password_state}

      not Token.blank?(user.provider) ->
        {:replay, :provider}

      not valid_email?(user.email) ->
        {:replay, :validation}

      not is_map(user.settings) or Settings.sanitize(user.settings) != {:ok, user.settings} ->
        {:replay, :settings_callback}

      not Payload.supported?(user) ->
        {:replay, :metadata}

      true ->
        {:ok, user}
    end
  end

  defp valid_email?(email) when is_binary(email),
    do: email == Account.normalize_email(email) and Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/u, email)

  defp valid_email?(_), do: false
end
