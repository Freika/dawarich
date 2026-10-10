defmodule Dawarich.Auth.AccountLink.Pending do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Recovery.{Settings, Token}
  alias Dawarich.Repo

  @required ~w(user_id provider uid expires_at)
  @allowed @required ++ ["provider_label"]
  @special ~w(invitation_token pending_import_ticket dawarich_client client referral partnero_referral
              otp_user_id otp_challenge_at otp_remember_me otp_failed_attempts)

  def valid(session, now, context) when is_map(session) and is_integer(now) do
    pending = session["pending_oauth_link"]

    with :ok <- supported_session(session, context),
         :ok <- shape(pending, now),
         {:ok, user} <- target(pending["user_id"], context) do
      {:ok, %{user: user, pending: pending, session: session}}
    end
  end

  def valid(_, _, _), do: {:handoff, :pending}

  defp supported_session(session, context) do
    cond do
      context[:self_hosted] != true ->
        {:handoff, :cloud}

      context[:remember] not in [nil, false] ->
        {:handoff, :remember}

      Enum.any?(@special, &Map.has_key?(session, &1)) ->
        {:handoff, :special_session}

      Enum.any?(Map.keys(session), fn key ->
        is_binary(key) and String.starts_with?(key, "warden.user.") and
            String.ends_with?(key, ".key")
      end) ->
        {:handoff, :authenticated}

      not attempts?(session["pending_oauth_link_attempts"]) ->
        {:handoff, :pending}

      true ->
        :ok
    end
  end

  defp shape(pending, now) when is_map(pending) do
    cond do
      not Enum.all?(@required, &Map.has_key?(pending, &1)) or
          Enum.any?(Map.keys(pending), &(&1 not in @allowed)) ->
        {:handoff, :pending}

      not id?(pending["user_id"]) or pending["provider"] != "openid_connect" ->
        {:handoff, :pending}

      not text?(pending["uid"]) or Token.blank?(pending["uid"]) ->
        {:handoff, :pending}

      not label?(pending["provider_label"]) ->
        {:handoff, :pending}

      not timestamp?(pending["expires_at"]) or pending["expires_at"] < now ->
        {:handoff, :pending}

      true ->
        :ok
    end
  end

  defp shape(_, _), do: {:handoff, :pending}

  defp target(id, context) do
    repo = Map.get(context, :repo, Repo)

    case repo.one(from(u in Account, where: u.id == ^id and is_nil(u.deleted_at)), log: false) do
      nil ->
        {:handoff, :actor}

      user ->
        case repo.query!("SELECT settings FROM users WHERE id=$1", [id], log: false).rows do
          [[settings]] -> support(%{user | settings: Dawarich.UserSettings.provided(settings)})
          [] -> {:handoff, :actor}
        end
    end
  end

  defp support(user) do
    cond do
      not Token.blank?(user.provider) or not Token.blank?(user.uid) ->
        {:handoff, :linked}

      user.status == 3 or not is_nil(user.locked_at) ->
        {:handoff, :actor}

      not email?(user.email) or not hash?(user.encrypted_password) ->
        {:handoff, :actor}

      not is_map(user.settings) or Settings.sanitize(user.settings) != {:ok, user.settings} ->
        {:handoff, :settings_callback}

      true ->
        {:ok, user}
    end
  end

  defp email?(email) when is_binary(email),
    do: email == Account.normalize_email(email) and Regex.match?(~r/\A[^@\s]+@[^@\s]+\z/u, email)

  defp email?(_), do: false

  defp hash?(hash) when is_binary(hash),
    do: Regex.match?(~r/\A\$2[ab]\$(0[4-9]|[12][0-9]|3[01])\$[.\/A-Za-z0-9]{53}\z/, hash)

  defp hash?(_), do: false
  defp id?(id), do: is_integer(id) and id > 0 and id <= 9_223_372_036_854_775_807
  defp attempts?(value), do: is_nil(value) or (is_integer(value) and value >= 0)
  defp label?(value), do: is_nil(value) or text?(value)

  defp text?(value),
    do: is_binary(value) and String.valid?(value) and not String.contains?(value, <<0>>)

  defp timestamp?(value) when is_integer(value), do: match?({:ok, _}, DateTime.from_unix(value))
  defp timestamp?(_), do: false
end
