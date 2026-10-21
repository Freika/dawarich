defmodule Dawarich.Auth.Otp.Lockout do
  @moduledoc false

  alias Dawarich.Mail.OtpAccountLockedWorker
  alias Dawarich.{RailsCache.Wire, Redis}

  def register_failed_attempt(repo, id, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)

    {:ok, transitioned} =
      repo.transaction(fn ->
        case repo.query!(
               "SELECT failed_otp_attempts,otp_locked_at FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
               [id],
               log: false
             ).rows do
          [[attempts, locked_at]] -> transition(repo, id, attempts, locked_at, now)
          [] -> false
        end
      end)

    if transitioned, do: notify(id, now, opts)
    :ok
  end

  def throttle_key(id), do: "otp_lockout_email_throttle/user/#{id}"

  defp transition(repo, id, attempts, locked_at, now) do
    cutoff = DateTime.add(now, -1800) |> DateTime.to_naive()

    if locked_at && NaiveDateTime.compare(locked_at, cutoff) == :gt do
      false
    else
      attempts = if locked_at, do: 1, else: attempts + 1
      lock = if attempts >= 10, do: DateTime.to_naive(now)

      repo.query!(
        "UPDATE users SET failed_otp_attempts=$2,otp_locked_at=$3 WHERE id=$1",
        [id, attempts, lock],
        log: false
      )

      not is_nil(lock)
    end
  end

  defp notify(id, now, opts) do
    bytes =
      Wire.encode_boolean(true,
        expires_at: DateTime.to_unix(now, :microsecond) / 1_000_000 + 3600
      )

    command = Keyword.get(opts, :cache_command, &Redis.cache_command/1)

    case command.(["SET", throttle_key(id), bytes, "NX", "PX", "3600000"]) do
      {:ok, "OK"} ->
        args = %{
          "user_id" => id,
          "locale" => Keyword.get(opts, :locale, "en"),
          "event_id" => Ecto.UUID.generate()
        }

        enqueue =
          Keyword.get(opts, :enqueue, fn payload ->
            Oban.insert!(Keyword.get(opts, :oban, Oban), OtpAccountLockedWorker.new(payload))
          end)

        enqueue.(args)

      {:ok, nil} ->
        :ok

      {:error, _} ->
        :ok
    end
  end
end
