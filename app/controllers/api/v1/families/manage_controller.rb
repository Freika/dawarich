# frozen_string_literal: true

class Api::V1::Families::ManageController < Api::V1::Families::ManagementBaseController
  before_action :ensure_family_feature_available!, only: %i[create update]

  def show
    render json: management_payload
  end

  def create
    authorize_management(Family.new, :create?)
    service = Families::Create.new(user: current_api_user, name: family_params[:name].to_s)
    return validation_failed(service.error_message.presence || service.errors.full_messages.first) unless service.call

    current_api_user.reload
    render json: management_payload, status: :created
  end

  def update
    family = management_family
    authorize_management(family, :update?)
    return validation_failed(family.errors.full_messages.first) unless family.update(family_params)

    render json: management_payload
  end

  def destroy
    family = management_family
    authorize_management(family, :destroy?)
    deleted = family.with_lock do
      next false if family.members.count > 1

      family.destroy!
      true
    end
    unless deleted
      message = I18n.t('controllers.families.cannot_delete_family_with_members_remove_all_members_first')
      return validation_failed(message)
    end

    head :no_content
  end

  private

  def family_params
    params.expect(family: [:name])
  end

  def management_payload
    Api::FamilyManagementSerializer.new(current_api_user).call
  end
end
