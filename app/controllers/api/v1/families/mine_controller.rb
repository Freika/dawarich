# frozen_string_literal: true

class Api::V1::Families::MineController < Api::V1::Families::BaseController
  include Api::FamilyErrorRendering

  # A Lapsed user — Membership intact, Entitlement gone — has to learn that from
  # a successful response rather than a refusal, which is indistinguishable from
  # never having been entitled. #show therefore replaces the inherited gates with
  # one that lets a Lapsed user through while leaving every other status code
  # exactly as it was. #create is for users in no family; #destroy stays open to
  # a lapsed owner so they can still dissolve the family, as on the web.
  skip_before_action :ensure_family_feature_available!, only: %i[show destroy]
  skip_before_action :ensure_user_in_family!, only: %i[show create]
  before_action :ensure_family_state_visible!, only: :show
  before_action :ensure_family_owner!, only: %i[update destroy]

  def show
    render json: serializer.call
  end

  def create
    service = Families::Create.new(user: current_api_user, name: name_param)
    return render_family_service_error(service) unless service.call

    render json: Api::FamilySerializer.new(current_api_user.reload).call, status: :created
  end

  def update
    family = current_api_user.family
    unless family.update(name: name_param.strip)
      return render_family_error(:invalid_name, family.errors.full_messages.first)
    end

    render json: Api::FamilySerializer.new(current_api_user.reload).call
  end

  def destroy
    family = current_api_user.family
    deleted = family.with_lock do
      next false if family.members.count > 1

      family.destroy
    end
    return render_family_error(:family_has_members) unless deleted

    head :no_content
  rescue ActiveRecord::InvalidForeignKey
    render_family_error(:family_has_members)
  end

  private

  # A non-string name (a number, an object) is treated as missing, so it is
  # refused as invalid instead of being stringified into a valid-looking name.
  def name_param
    params[:name].is_a?(String) ? params[:name] : ''
  end

  def ensure_family_owner!
    return if FamilyPolicy.new(current_api_user, current_api_user.family).destroy?

    render_family_error(:owner_required)
  end

  def ensure_family_state_visible!
    return if current_api_user&.in_family? && current_api_user.feature_enabled?(:family)
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
