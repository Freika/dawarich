defmodule Dawarich.Auth.CredentialsClosure do
  @moduledoc false
  alias Dawarich.{Accounts, RailsSecret}
  alias Dawarich.Auth.Recovery.{MailWorker, Notification, Token}

  def authenticate(repo, user, password, valid, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    locked = not Accounts.unlocked?(user, now)

    user =
      if user.locked_at && not locked do
        repo.update!(
          Ecto.Changeset.change(user, %{failed_attempts: 0, locked_at: nil, unlock_token: nil}),
          log: false
        )
      else
        user
      end

    cond do
      valid and user.otp_required_for_login and not locked and user.failed_attempts < 9 ->
        {:handoff, :otp}

      valid and not locked and user.failed_attempts < 9 ->
        {:ok, user}

      true ->
        failure(repo, user, password, locked, now, context)
    end
  end

  defp failure(repo, user, password, locked, now, context) do
    increment =
      if not locked and not user.otp_required_for_login and String.trim(password) == "",
        do: 1,
        else: 2

    attempts = user.failed_attempts + increment
    changes = %{failed_attempts: attempts}

    changes =
      if attempts >= 10 and not locked,
        do: Map.merge(changes, %{locked_at: now, updated_at: now}),
        else: changes

    user = repo.update!(Ecto.Changeset.change(user, changes), log: false)
    if not locked and attempts >= 10, do: notify_lock(repo, user, now, context)
    {:error, :invalid}
  end

  defp notify_lock(repo, user, _now, context) do
    secret = Map.get_lazy(context, :secret, &RailsSecret.fetch/0)
    raw = Token.raw()
    digest = Token.digest(:unlock_token, raw, secret)
    repo.update!(Ecto.Changeset.change(user, %{unlock_token: digest}), log: false)

    intent = %Notification{
      kind: :unlock_instructions,
      user_id: user.id,
      raw: raw,
      digest: digest,
      locale: Map.get(context, :locale, "en")
    }

    Map.get(context, :enqueue, &MailWorker.enqueue/1).(intent)
  end

  def client_ip(conn), do: {:ok, DawarichWeb.RackIp.ip(conn)}
end
