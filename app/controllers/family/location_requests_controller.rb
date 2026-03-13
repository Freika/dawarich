# frozen_string_literal: true

class Family::LocationRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :ensure_user_in_family!
  before_action :set_request, only: %i[show accept decline]
  before_action :authorize_target_user!, only: %i[show accept decline]

  def create
    target = User.find(params[:target_user_id])
    result = Families::CreateLocationRequest.new(requester: current_user, target_user: target).call

    if result.success?
      redirect_to family_path, notice: 'Location request sent successfully'
    else
      redirect_to family_path, alert: result.payload[:message]
    end
  end

  def show
    # View rendered by template
  end

  def accept
    unless actionable?
      redirect_to family_path, alert: 'This request has expired or already been responded to'
      return
    end

    duration = params[:duration] || @request.suggested_duration
    current_user.update_family_location_sharing!(true, duration: duration)
    @request.update!(status: :accepted, responded_at: Time.current)

    redirect_to family_path, notice: 'Location sharing enabled'
  end

  def decline
    unless actionable?
      redirect_to family_path, alert: 'This request has expired or already been responded to'
      return
    end

    @request.update!(status: :declined, responded_at: Time.current)

    redirect_to family_path, notice: 'Location request declined'
  end

  private

  def set_request
    @request = Family::LocationRequest.find(params[:id])
  end

  def authorize_target_user!
    return if @request.target_user == current_user

    redirect_to family_path, alert: 'You are not authorized to view this request'
  end

  def ensure_user_in_family!
    return if current_user&.in_family?

    redirect_to root_path, alert: 'You must be part of a family'
  end

  def actionable?
    @request.pending? && @request.expires_at > Time.current
  end
end
