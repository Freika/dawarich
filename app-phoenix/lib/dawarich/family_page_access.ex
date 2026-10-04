defmodule Dawarich.FamilyPageAccess do
  @moduledoc false

  alias Dawarich.Entitlements
  alias Dawarich.Families.Sharing

  def validate_settings!(%{} = settings) do
    if settings["timezone"] != nil and not is_binary(settings["timezone"]),
      do: raise(ArgumentError, "unsupported timezone type")

    config = Sharing.config(settings) || %{}

    for key <- ~w(duration expires_at history_window) do
      if config[key] != nil and not is_binary(config[key]),
        do: raise(ArgumentError, "unsupported sharing value")
    end

    config
  end

  def validate_settings!(_settings), do: raise(ArgumentError, "unsupported settings type")

  def member([id, email, membership_id, role, joined_at, settings, latest], now) do
    config = validate_settings!(settings)
    enabled = Sharing.enabled?(settings, now)

    %{
      id: id,
      email: email,
      membership_id: membership_id,
      role: role,
      joined_at: joined_at,
      latest_timestamp: if(enabled, do: latest),
      sharing: %{
        enabled?: enabled,
        duration: config["duration"] || "permanent",
        expires_at: config["expires_at"],
        share_history?: config["share_history"] == true,
        history_window: config["history_window"] || "7d"
      }
    }
  end

  def available?(user, family, self_hosted, now) do
    self_hosted or
      (family != nil and
         Entitlements.inherited?(family.access_until, family.owner_plan, family.owner_until, now)) or
      (user.plan == 2 and Entitlements.future?(user.active_until, now))
  end

  def state(user, nil, :new, self_hosted, _now),
    do: {:page, if(self_hosted or user.plan == 2, do: :create, else: :upgrade)}

  def state(user, nil, {:request, _id}, self_hosted, now) do
    if available?(user, nil, self_hosted, now),
      do: {:redirect, "/", :not_in_family},
      else: {:redirect, "/family/new", :feature_unavailable}
  end

  def state(_user, nil, _action, _self_hosted, _now),
    do: {:redirect, "/family/new", :not_in_family}

  def state(user, family, :new, self_hosted, now) do
    if available?(user, family, self_hosted, now),
      do: {:redirect, "/family", nil},
      else: {:page, :lapsed}
  end

  def state(user, family, action, self_hosted, now) do
    cond do
      action != :invitations and not available?(user, family, self_hosted, now) ->
        {:redirect, "/family/new", :feature_unavailable}

      action == :edit and family.role != 0 ->
        {:redirect, "/", :not_authorized}

      true ->
        {:page, action}
    end
  end
end
