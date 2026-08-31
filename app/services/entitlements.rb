# frozen_string_literal: true

class Entitlements
  def self.for(user)
    new(user)
  end

  def initialize(user)
    @user = user
  end

  def effective_plan
    return @user.plan.to_sym if self_hosted?
    return :family if inherited_family_access?

    @user.plan.to_sym
  end

  def inherited_family_access?
    return false unless @user.in_family?

    family = @user.family
    return family.access_until.future? if family&.access_until

    owner = family&.owner
    return false unless owner&.family?

    owner.active_until&.future? || false
  end

  def full_access?
    self_hosted? || effective_plan != :lite
  end

  def restricted?
    !full_access?
  end

  def write_api?
    full_access?
  end

  def pro_api?
    full_access?
  end

  def integrations?
    full_access?
  end

  def public_sharing?
    full_access?
  end

  def families?
    self_hosted? || effective_plan == :family
  end

  def data_window
    return if full_access?

    DawarichSettings::LITE_DATA_WINDOW
  end

  def data_window_start
    data_window&.ago
  end

  def unlimited_points?
    self_hosted?
  end

  def points_limit
    return if unlimited_points?

    DawarichSettings::BASIC_PAID_PLAN_LIMIT
  end

  private

  def self_hosted?
    DawarichSettings.self_hosted?
  end
end
