# frozen_string_literal: true

class Entitlements
  def initialize(user)
    @user = user
  end

  def effective_plan
    return @user.plan.to_sym if self_hosted?
    return :family if inherited_family_access?

    @user.plan.to_sym
  end

  # A self-hosted instance has no Lite limits, whatever plan the row carries.
  def map_plan
    full_access? && effective_plan == :lite ? :pro : effective_plan
  end

  def inherited_family_access?
    (@user.in_family? && @user.family&.access_live?) || false
  end

  def full_access?
    self_hosted? || effective_plan != :lite
  end

  def restricted?
    !full_access?
  end

  def families?
    return true if self_hosted?
    return true if inherited_family_access?

    @user.family? && (@user.active_until&.future? || false)
  end

  # Whether the account may write: web, API and imports all ask this.
  def in_good_standing?
    return false unless @user.active? || @user.trial?

    self_hosted? || @user.active_until&.future? || false
  end

  def can_create_family?
    self_hosted? || @user.family?
  end

  def data_window
    return if full_access?

    DawarichSettings::LITE_DATA_WINDOW
  end

  def data_window_start
    DawarichSettings.lite_data_window_start if data_window
  end

  def unlimited_points?
    self_hosted?
  end

  def points_limit
    return if unlimited_points?

    DawarichSettings::BASIC_PAID_PLAN_LIMIT
  end

  def webhook_limits?
    !self_hosted?
  end

  private

  def self_hosted?
    DawarichSettings.self_hosted?
  end
end
