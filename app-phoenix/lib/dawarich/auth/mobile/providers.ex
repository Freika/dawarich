defmodule Dawarich.Auth.Mobile.Providers do
  @moduledoc false
  alias Dawarich.Auth.Providers.{Google, Accounts}
  alias Dawarich.Auth.Apple.Verify
  alias Dawarich.Auth.Mobile.Payload

  def exchange(provider, params, context) do
    context = Map.put(context, :nonce, params["nonce"])

    verify =
      if provider == "apple",
        do: Verify.call(params["id_token"], context),
        else: Google.verify_id_token(params["id_token"], context)

    case verify do
      {:ok, claims} ->
        resolve(provider, claims, context)

      _ ->
        detail = if params["id_token"] in [nil, ""], do: "blank token", else: "invalid token"

        {:auth_error, 401, "controllers.api.v1.auth.#{provider}.token_verification_failed",
         %{"message" => detail}}
    end
  end

  defp resolve(provider, claims, context) do
    identity = %{
      provider: if(provider == "apple", do: "apple", else: "google_oauth2"),
      uid: claims["sub"],
      email: claims["email"],
      email_verified: claims["email_verified"] in [true, "true"],
      first_name: nil,
      last_name: nil
    }

    case Accounts.resolve(identity, context) do
      {:ok, user, created} ->
        if created and context[:self_hosted] == false do
          callback = get_in(context, [:callbacks, :webhook])

          if not is_function(callback, 1) or callback.(user.id) != :ok,
            do: raise("Signup callback unavailable")
        end

        Payload.success(user, created, context)

      {:link_required, link} ->
        if link.rate_limited do
          {:retry_after, link.retry_after, Payload.error(provider, :rate_limited, context)}
        else
          Payload.error(provider, :verification_sent, context)
        end

      {:error, reason} ->
        Payload.error(provider, reason, context)
    end
  end
end
