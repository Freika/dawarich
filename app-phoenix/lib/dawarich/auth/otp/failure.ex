defmodule Dawarich.Auth.Otp.Failure do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Otp.Pending
  alias Dawarich.{RailsCache.Wire, Redis, Repo}

  def record(session, context) do
    repo = Map.get(context, :repo, Repo)
    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    {:ok, result} =
      repo.transaction(fn ->
        case Pending.valid(session, DateTime.to_unix(now)) do
          {:ok, id, _} ->
            user =
              repo.one(
                from(u in Account,
                  where: u.id == ^id and is_nil(u.deleted_at),
                  lock: "FOR UPDATE"
                ),
                log: false
              )

            failure(repo, user, session, now, context)

          _ ->
            {:redirect, Pending.clear(session), :session_expired_please_sign_in_again}
        end
      end)

    result
  end

  defp failure(_repo, nil, session, _now, _context),
    do: {:redirect, Pending.clear(session), :session_expired_please_sign_in_again}

  defp failure(repo, user, session, now, context) do
    locked =
      user.otp_locked_at && DateTime.compare(user.otp_locked_at, DateTime.add(now, -1800)) == :gt

    if locked do
      {:redirect, Pending.clear(session),
       :account_temporarily_locked_due_to_too_many_failed_2fa_attempts}
    else
      count = if user.otp_locked_at, do: 1, else: user.failed_otp_attempts + 1
      changes = %{failed_otp_attempts: count, otp_locked_at: if(count >= 10, do: now)}
      user = repo.update!(Ecto.Changeset.change(user, changes), log: false)
      delivery = if count >= 10, do: notify(user, now, context), else: :ok
      failures = session["otp_failed_attempts"] || 0

      if not is_integer(failures) do
        {:error, :pending}
      else
        session = Map.put(session, "otp_failed_attempts", failures + 1)

        cond do
          delivery != :ok ->
            {:error, :delivery_owner}

          failures + 1 >= 5 ->
            {:redirect, Pending.clear(session),
             :too_many_invalid_two_factor_codes_please_sign_in_again}

          true ->
            {:form, session, :invalid_two_factor_code}
        end
      end
    end
  end

  defp notify(user, now, context) do
    epoch = DateTime.to_unix(now, :microsecond) / 1_000_000
    bytes = Wire.encode_boolean(true, expires_at: epoch + 3600)
    command = Map.get(context, :cache_command, &Redis.cache_command/1)

    case command.([
           "SET",
           "otp_lockout_email_throttle/user/#{user.id}",
           bytes,
           "NX",
           "PX",
           "3600000"
         ]) do
      {:ok, "OK"} -> Map.get(context, :enqueue_otp_lock, fn _ -> {:error, :mail_owner} end).(user)
      {:ok, nil} -> :ok
      _ -> {:error, :cache}
    end
  end
end
