defmodule Dawarich.AccountApi.Closure do
  @moduledoc false
  alias Dawarich.{
    Entitlements,
    I18n,
    RailsTime,
    ReleaseMigration,
    SubscriptionToken,
    UserTimeZone
  }

  @plans %{0 => "lite", 1 => "pro", 2 => "family"}
  @statuses %{nil => nil, 0 => "inactive", 1 => "active", 2 => "trial", 3 => "pending_payment"}
  @sources %{nil => nil, 0 => "none", 1 => "paddle", 2 => "apple_iap", 3 => "google_play"}
  @feature_keys ~w(heatmap fog_of_war scratch_map globe_view integrations write_api sharing full_digest data_window)

  def hosted?, do: ReleaseMigration.self_hosted?()
  def full?(user, now), do: Entitlements.full_access?(user, hosted?(), now)
  def family?(user, now), do: Entitlements.families?(user, hosted?(), now)

  def plan(user, now) do
    with {:ok, until} <- RailsTime.iso8601(user.active_until, zone(user.timezone)) do
      {full, effective} = Entitlements.access(user, hosted?(), now)

      {:ok,
       {:object,
        [
          {"plan", Map.fetch!(@plans, user.plan)},
          {"effective_plan", effective},
          {"status", Map.fetch!(@statuses, user.status)},
          {"subscription_source", Map.fetch!(@sources, user.subscription_source)},
          {"active_until", until},
          {"features", features(full)}
        ]}}
    end
  rescue
    _ -> {:error, 500}
  end

  def subscription(user, until),
    do:
      {:object,
       [
         {"status", Map.fetch!(@statuses, user.status)},
         {"active_until", until},
         {"plan", Map.fetch!(@plans, user.plan)}
       ]}

  def pending(user, now) do
    if user.status == 3 do
      {:ok, 402,
       {:object,
        [
          {"error", "payment_required"},
          {"message", I18n.en!("controllers.api.complete_your_subscription_to_continue")},
          {"resume_url", upgrade_url(user, now)}
        ]}}
    else
      :ok
    end
  end

  def upgrade_url(user, now), do: if(hosted?(), do: nil, else: SubscriptionToken.url(user, now))

  def zone(value) when is_binary(value) or is_nil(value),
    do: UserTimeZone.name(%{"timezone" => value})

  def zone(_), do: raise(ArgumentError)

  defp features(true),
    do: {:object, Enum.map(@feature_keys, &{&1, if(&1 == "data_window", do: nil, else: true)})}

  defp features(false),
    do:
      {:object,
       Enum.map(@feature_keys, fn key ->
         {key,
          case key do
            "write_api" -> "create_only"
            "data_window" -> "12_months"
            _ -> false
          end}
       end)}
end
