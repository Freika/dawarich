defmodule Dawarich.Auth.Api.Login do
  @moduledoc false
  alias Dawarich.Auth.{Account, Api.Actor, Api.BcryptWork, Api.Payload}
  alias Dawarich.Auth.Recovery.Token
  alias Dawarich.Auth.TwoFactor.{ApiActor, Secret, Totp}

  def prepare(email, password, context) when is_binary(email) and is_binary(password) do
    with true <- String.valid?(email) and String.valid?(password),
         true <- email == String.replace(email, ~r/[^\x00-\x7F]/u, ""),
         false <- String.contains?(password, <<0>>),
         {:ok, user} <- actor(Account.normalize_email(email), password, context),
         true <- ApiActor.password_valid?(user, password),
         {:ok, payload} <- Payload.read(user, context) do
      select(user, payload, context)
    else
      {:replay, _} = replay -> replay
      _ -> {:replay, :credentials}
    end
  rescue
    _ in [ArgumentError, ErlangError] -> {:replay, :credentials}
  end

  def prepare(_, _, _), do: {:replay, :parameters}

  defp actor(email, password, context) do
    case Actor.for_password(email, context) do
      {:replay, reason, _} when reason in [:blank_password_state, :uncomputable_password_state] ->
        dummy_work(password, context, 2)
        {:replay, reason}

      {:replay, :invalid_password_state, _} ->
        {:replay, :invalid_password_state}

      {:replay, :password_state, user} ->
        rejected_password_work(user, password)
        {:replay, :password_state}

      {:replay, reason, user} ->
        ApiActor.password_valid?(user, password)
        {:replay, reason}

      {:replay, reason} = replay when reason != :context ->
        dummy_work(password, context, 1)
        replay

      result ->
        result
    end
  end

  defp rejected_password_work(user, password) do
    if not Token.blank?(password), do: BcryptWork.compare(user.encrypted_password, password)
  end

  defp dummy_work(password, context, count) do
    if not Token.blank?(password) do
      opts = Keyword.take(Map.to_list(context), [:log_rounds])
      for _ <- 1..count, do: Bcrypt.no_user_verify(opts)
    end
  end

  defp select(%{otp_required_for_login: true} = user, _payload, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)

    with true <- Secret.available?(env),
         {:ok, secret} when is_binary(secret) <- Secret.decrypt(user.otp_secret, env) do
      Totp.decode(secret)
      {:challenge, user}
    else
      _ -> {:replay, :encryption}
    end
  end

  defp select(%{otp_required_for_login: false} = user, payload, _),
    do: {:success, user, payload}

  defp select(_, _, _), do: {:replay, :otp_state}
end
