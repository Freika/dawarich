defmodule Dawarich.Auth.Api.ChallengeWork do
  @moduledoc false
  alias Dawarich.ActiveRecordEncryption
  alias Dawarich.Auth.Api.BcryptWork
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.Auth.TwoFactor.{BackupCodes, Secret, Totp}

  def prepare(user, code, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()

    if user.otp_locked_at && DateTime.compare(user.otp_locked_at, DateTime.add(now, -1800)) == :gt do
      result = backup(user, code, context)
      admitted(result, user, readable?(user, context))
    else
      env = Map.get_lazy(context, :env, &System.get_env/0)

      with {:ok, secret} <- decrypt(user.otp_secret, env) do
        result =
          if not Token.blank?(code) and not Token.blank?(secret) do
            case Totp.verify(secret, code, DateTime.to_unix(now), user.consumed_timestep) do
              {:ok, timestep} -> {:ok, :totp, %{consumed_timestep: timestep}}
              :invalid -> backup(user, code, context)
            end
          else
            backup(user, code, context)
          end

        admitted(
          result,
          user,
          Secret.available?(env) and is_binary(secret) and not Token.blank?(secret)
        )
      end
    end
  rescue
    _ in [ArgumentError, ErlangError] -> {:replay, :otp_state}
  end

  defp decrypt(nil, _), do: {:ok, nil}

  defp decrypt(ciphertext, env) do
    with {:ok, key} <- ActiveRecordEncryption.key(env),
         do: ActiveRecordEncryption.decrypt(ciphertext, key)
  end

  defp readable?(user, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)

    with true <- Secret.available?(env),
         {:ok, secret} when is_binary(secret) <- decrypt(user.otp_secret, env),
         false <- Token.blank?(secret) do
      Totp.decode(secret)
      true
    else
      _ -> false
    end
  end

  defp admitted(result, user, secret?) do
    if secret? and is_integer(user.failed_otp_attempts) and
         BackupCodes.supported?(user.otp_backup_codes),
       do: result,
       else: {:replay, :otp_state}
  end

  defp backup(user, code, context) do
    hashes = user.otp_backup_codes || []
    opts = Map.get(context, :backup_options, [])

    if is_list(hashes) do
      Enum.reduce_while(hashes, {:replay, :invalid_code}, fn hash, _ ->
        case BcryptWork.compare(hash, code, opts) do
          {:ok, true} ->
            {:halt, {:ok, :backup, %{otp_backup_codes: Enum.reject(hashes, &(&1 == hash))}}}

          {:ok, false} ->
            {:cont, {:replay, :invalid_code}}

          replay ->
            {:halt, replay}
        end
      end)
    else
      {:replay, :backup_state}
    end
  end
end
