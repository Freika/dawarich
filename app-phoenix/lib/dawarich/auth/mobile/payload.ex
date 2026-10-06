defmodule Dawarich.Auth.Mobile.Payload do
  @moduledoc false
  alias Dawarich.Auth.Api.Payload
  alias DawarichWeb.Translate

  def success(user, created, context) do
    case read(user, context) do
      {:ok, payload} -> {:success, if(created, do: 201, else: 200), payload}
      _ -> {:error, 422, %{"error" => "invalid_authentication_data"}}
    end
  end

  def read(user, context) do
    with {:ok, {:object, pairs}} <- Payload.read(user, context) do
      now = Map.get(context, :clock, &DateTime.utc_now/0).()
      {_, effective} = Dawarich.Entitlements.access(user, context[:self_hosted] != false, now)

      {:ok,
       {:object,
        Enum.map(pairs, fn
          {"effective_plan", _} -> {"effective_plan", effective}
          pair -> pair
        end)}}
    end
  end

  def error(provider, reason, context) do
    prefix = "controllers.api.v1.auth." <> provider <> "."

    {status, code, key} =
      case reason do
        :unverified_email ->
          {403, "email_not_verified",
           provider <> "_has_not_verified_this_email_sign_in_with_password"}

        :missing_email ->
          {422, "apple_email_missing", "we_couldn_t_find_your_existing_account_and_apple_didn"}

        :pending_deletion ->
          {409, "account_pending_deletion", :pending_deletion}

        :verification_sent ->
          {202, "verification_sent", "this_email_already_has_a_dawarich_account_we_sent_a"}

        :rate_limited ->
          {429, "verification_rate_limited", "verification_rate_limited"}

        _ ->
          {503, "authentication_unavailable", nil}
      end

    key =
      if key == :pending_deletion,
        do: "controllers.api.v1.auth.account_pending_deletion",
        else: key && prefix <> key

    message =
      if key,
        do: Translate.t(Map.get(context, :locale, "en"), key, %{}),
        else: "Authentication unavailable"

    {:error, status, %{"error" => code, "message" => message}}
  end
end
