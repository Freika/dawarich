defmodule Dawarich.Auth.Api.Refusals do
  @moduledoc false
  import Ecto.Query

  alias Dawarich.Auth.{
    Account,
    Api.ChallengeCache,
    Api.ChallengeToken,
    Api.ChallengeWork,
    Api.ChallengeWrite,
    Mobile.Payload
  }

  alias Dawarich.Auth.TwoFactor.{ApiActor, Secret}
  alias Dawarich.{Repo, RailsCache.Wire, Redis}

  def login(params, context) do
    env = Map.get_lazy(context, :env, &System.get_env/0)

    if context[:oidc] == true and Map.get(env, "ALLOW_EMAIL_PASSWORD_LOGIN", "true") != "true" do
      error(
        403,
        "controllers.users.sessions.email_password_login_is_disabled_please_use_oidc_to_sign"
      )
    else
      email = Account.normalize_email(scalar(params["email"]))

      user =
        repo(context).one(from(u in Account, where: u.email == ^email and is_nil(u.deleted_at)),
          log: false
        )

      password = scalar(params["password"])

      authenticated =
        if user, do: ApiActor.password_valid?(user, password), else: dummy(password, context)

      cond do
        not authenticated ->
          error(401, "controllers.api.v1.auth.sessions.invalid_credentials")

        Secret.available?(env) and user.otp_required_for_login ->
          case ChallengeToken.issue(user.id, context) do
            {:ok, token} -> {:challenge, token}
            _ -> {:error, 503, %{"error" => "authentication_unavailable"}}
          end

        true ->
          success(user, context)
      end
    end
  rescue
    _ -> {:error, 422, %{"error" => "invalid_authentication_data"}}
  end

  def challenge(params, context) do
    with {:ok, claims} <- ChallengeToken.verify(params["challenge_token"], context),
         {:ok, false} <- consumed?(claims["jti"], context),
         user when not is_nil(user) <-
           repo(context).one(
             from(u in Account, where: u.id == ^claims["user_id"] and is_nil(u.deleted_at)),
             log: false
           ) do
      redeem(user, claims, scalar(params["otp_code"]) |> Account.strip(), context)
    else
      _ ->
        error(401, "controllers.api.v1.auth.otp_challenges.invalid_challenge", %{
          "message" => token_detail(params["challenge_token"])
        })
    end
  end

  def consumed?(jti, context), do: ChallengeCache.exists?(jti, context)

  defp redeem(user, claims, code, context) do
    case ChallengeWork.prepare(user, code, context) do
      {:ok, kind, changes} ->
        with {:ok, payload} <- Payload.read(user, context) do
          prepared = %{
            user: user,
            kind: kind,
            changes: changes,
            payload: payload,
            jti: claims["jti"]
          }

          {:ok, payload} = ChallengeWrite.commit(prepared, context)
          {:success, 200, payload}
        else
          _ -> {:error, 422, %{"error" => "invalid_authentication_data"}}
        end

      {:replay, :invalid_code} ->
        if locked?(user, context) do
          error(423, "controllers.api.v1.auth.otp_challenges.account_locked")
        else
          failed(user, context)
          error(401, "controllers.api.v1.auth.otp_challenges.invalid_two_factor_code")
        end

      _ ->
        {:error, 422, %{"error" => "invalid_authentication_data"}}
    end
  end

  defp failed(user, context) do
    repo = repo(context)
    now = clock(context)

    if user.otp_locked_at,
      do:
        repo.query!(
          "UPDATE users SET failed_otp_attempts=0,otp_locked_at=NULL WHERE id=$1",
          [user.id],
          log: false
        )

    [[count]] =
      repo.query!(
        "UPDATE users SET failed_otp_attempts=failed_otp_attempts+1 WHERE id=$1 RETURNING failed_otp_attempts",
        [user.id],
        log: false
      ).rows

    if count >= 10 do
      updated =
        repo.query!(
          "UPDATE users SET otp_locked_at=$2 WHERE id=$1 AND otp_locked_at IS NULL RETURNING id",
          [user.id, DateTime.to_naive(now)],
          log: false
        ).rows

      if updated != [] do
        bytes = Wire.encode_boolean(true, expires_at: DateTime.to_unix(now) + 3600)
        command = Map.get(context, :cache_command, &Redis.cache_command/1)

        if command.([
             "SET",
             "otp_lockout_email_throttle/user/#{user.id}",
             bytes,
             "NX",
             "PX",
             "3600000"
           ]) == {:ok, "OK"} do
          :ok =
            Map.get(context, :enqueue_otp_lock, fn _ -> {:error, :mail_owner} end).(
              repo.get!(Account, user.id)
            )
        end
      end
    end
  end

  defp success(user, context) do
    case Payload.read(user, context) do
      {:ok, payload} -> {:success, 200, payload}
      _ -> {:error, 422, %{"error" => "invalid_authentication_data"}}
    end
  end

  defp locked?(user, context),
    do:
      user.otp_locked_at &&
        DateTime.compare(user.otp_locked_at, DateTime.add(clock(context), -1800)) == :gt

  defp dummy(password, context) do
    Bcrypt.no_user_verify(log_rounds: Map.get(context, :log_rounds, 12))
    is_binary(password) and false
  end

  defp token_detail(token),
    do:
      if(is_binary(token) and length(String.split(token, ".")) != 3,
        do: "Not enough or too many segments",
        else: "invalid token"
      )

  defp scalar(value) when is_binary(value), do: value
  defp scalar(nil), do: ""
  defp scalar(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp scalar(_), do: ""
  defp error(status, key, bindings \\ %{}), do: {:auth_error, status, key, bindings}
  defp repo(context), do: Map.get(context, :repo, Repo)
  defp clock(context), do: Map.get(context, :clock, &DateTime.utc_now/0).()
end
