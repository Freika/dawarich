defmodule Dawarich.Auth.Api.Challenge do
  @moduledoc false
  alias Dawarich.Auth.Account
  alias Dawarich.Auth.Api.{Actor, ChallengeCache, ChallengeToken, ChallengeWork, Payload}

  def prepare(token, code, context) when is_binary(code) do
    with true <- String.valid?(code) and not String.contains?(code, <<0>>),
         {:ok, claims} <- ChallengeToken.verify(token, context),
         {:ok, false} <- ChallengeCache.exists?(claims["jti"], context),
         {:ok, user, admitted?} <- actor(claims["user_id"], context),
         {:ok, kind, changes} <- ChallengeWork.prepare(user, Account.strip(code), context),
         true <- admitted? and user.otp_required_for_login == true,
         {:ok, payload} <- Payload.read(user, context) do
      {:ok, %{user: user, kind: kind, changes: changes, payload: payload, jti: claims["jti"]}}
    else
      _ -> {:replay, :challenge}
    end
  rescue
    _ in [ArgumentError, ErlangError] -> {:replay, :challenge}
  end

  def prepare(_, _, _), do: {:replay, :parameters}

  defp actor(id, context) do
    case Actor.for_challenge(id, context) do
      {:ok, user} -> {:ok, user, true}
      {:replay, _, user} -> {:ok, user, false}
      replay -> replay
    end
  end
end
