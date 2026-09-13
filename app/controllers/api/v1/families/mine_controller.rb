# frozen_string_literal: true

class Api::V1::Families::MineController < Api::V1::Families::BaseController
  # A Lapsed user — Membership intact, Entitlement gone — has to learn that from
  # a successful response rather than a refusal, which is indistinguishable from
  # never having been entitled. This endpoint therefore replaces the inherited
  # gates with one that lets a Lapsed user through while leaving every other
  # status code exactly as it was.
  skip_before_action :ensure_family_feature_available!
  skip_before_action :ensure_user_in_family!
  before_action :ensure_family_state_visible!

  def show
    render json: serializer.call
  end

  private

  def ensure_family_state_visible!
    return if current_api_user&.in_family?
    return ensure_family_feature_available! unless entitled?

    ensure_user_in_family!
  end

  def entitled?
    DawarichSettings.family_feature_available_for?(current_api_user)
  end

  def serializer
    return Api::LapsedFamilySerializer.new(current_api_user) unless entitled?

    Api::FamilySerializer.new(current_api_user)
  end
end
