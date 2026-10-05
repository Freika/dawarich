defmodule Dawarich.Auth.Api.Payload do
  @moduledoc false
  alias Dawarich.{Entitlements, RailsTime}

  @statuses %{0 => "inactive", 1 => "active", 2 => "trial", 3 => "pending_payment"}
  @plans %{0 => "lite", 1 => "pro", 2 => "family"}
  @sources %{0 => "none", 1 => "paddle", 2 => "apple_iap", 3 => "google_play"}

  def supported?(user),
    do:
      Map.has_key?(@statuses, user.status) and Map.has_key?(@plans, user.plan) and
        Map.has_key?(@sources, user.subscription_source) and is_binary(user.api_key) and
        user.api_key != "" and
        (is_nil(user.active_until) or match?(%DateTime{}, user.active_until))

  def read(user, context) do
    if supported?(user) do
      now = Map.get(context, :clock, &DateTime.utc_now/0).()
      {true, effective_plan} = Entitlements.access(user, true, now)
      zone = Map.get(context, :timezone, System.get_env("TIME_ZONE", "Europe/Berlin"))
      zone = if zone == "UTC", do: "Etc/UTC", else: zone
      at = if user.active_until, do: DateTime.to_naive(user.active_until)

      with {:ok, stamp} <- RailsTime.iso8601(at, zone) do
        {:ok,
         {:object,
          [
            {"user_id", user.id},
            {"email", user.email},
            {"api_key", user.api_key},
            {"status", Map.fetch!(@statuses, user.status)},
            {"plan", Map.fetch!(@plans, user.plan)},
            {"effective_plan", effective_plan},
            {"subscription_source", Map.fetch!(@sources, user.subscription_source)},
            {"active_until", stamp}
          ]}}
      end
    else
      {:replay, :metadata}
    end
  end
end
