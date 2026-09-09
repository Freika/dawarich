# frozen_string_literal: true

class Family::LocationRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_available!
  before_action :ensure_user_in_family!
  before_action :set_request, only: %i[show accept decline]
  before_action :authorize_target_user!, only: %i[show accept decline]

  def create
    target = current_user.family&.members&.find_by(id: params[:target_user_id])

    unless target
      redirect_to family_path, alert: I18n.t('controllers.family.location_requests.user_not_found_in_your_family')
      return
    end

    result = Families::CreateLocationRequest.new(requester: current_user, target_user: target).call

    if result.success?
      redirect_to family_path, notice: I18n.t('controllers.family.location_requests.location_request_sent_successfully')
    else
      redirect_to family_path, alert: result.payload[:message]
    end
  end

  def show
    # View rendered by template
  end

  def accept
    result = Families::RespondToLocationRequest.new(
      request: @request, responder: current_user, decision: :accept, duration: params[:duration]
    ).call

    if result.success?
      redirect_to family_path, notice: I18n.t('controllers.family.location_requests.location_sharing_enabled')
    else
      redirect_to family_path, alert: result.payload[:message]
    end
  end

  def decline
    result = Families::RespondToLocationRequest.new(
      request: @request, responder: current_user, decision: :decline
    ).call

    if result.success?
      redirect_to family_path, notice: I18n.t('controllers.family.location_requests.location_request_declined')
    else
      redirect_to family_path, alert: result.payload[:message]
    end
  end

  private

  def set_request
    @request = Family::LocationRequest.where(family: current_user.family).find(params[:id])
  end

  def authorize_target_user!
    return if @request.target_user == current_user

    redirect_to family_path,
                alert: I18n.t('controllers.family.location_requests.you_are_not_authorized_to_view_this_request')
  end

  def ensure_user_in_family!
    return if current_user&.in_family?

    redirect_to root_path, alert: I18n.t('controllers.family.location_requests.you_must_be_part_of_a_family')
  end
end
