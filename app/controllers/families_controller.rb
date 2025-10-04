# frozen_string_literal: true

class FamiliesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :set_family, only: %i[show edit update destroy update_location_sharing]

  def show
    authorize @family

    @members = @family.members.includes(:family_membership).order(:email)
    @pending_invitations = @family.active_invitations.order(:created_at)

    @member_count = @family.member_count
    @can_invite = @family.can_add_members?
  end

  def new
    redirect_to family_path and return if current_user.in_family?

    @family = Family.new
    authorize @family
  end

  def create
    @family = Family.new(family_params)
    authorize @family

    service = Families::Create.new(
      user: current_user,
      name: family_params[:name]
    )

    if service.call
      redirect_to family_path, notice: 'Family created successfully!'
    else
      @family = Family.new(family_params)

      if service.errors.any?
        service.errors.each do |error|
          @family.errors.add(error.attribute, error.message)
        end
      end

      if service.error_message.present?
        @family.errors.add(:base, service.error_message)
      end

      flash.now[:alert] = service.error_message || 'Failed to create family'
      render :new, status: :unprocessable_content
    end
  end

  def edit
    authorize @family
  end

  def update
    authorize @family

    if @family.update(family_params)
      redirect_to family_path, notice: 'Family updated successfully!'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @family

    if @family.members.count > 1
      redirect_to family_path, alert: 'Cannot delete family with members. Remove all members first.'
    else
      @family.destroy
      redirect_to new_family_path, notice: 'Family deleted successfully!'
    end
  end

  def update_location_sharing
    enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    duration = params[:duration]

    if current_user.update_family_location_sharing!(enabled, duration: duration)
      response_data = {
        success: true,
        enabled: enabled,
        duration: current_user.family_sharing_duration,
        message: build_sharing_message(enabled, duration)
      }

      if enabled && current_user.family_sharing_expires_at.present?
        response_data[:expires_at] = current_user.family_sharing_expires_at.iso8601
        response_data[:expires_at_formatted] = current_user.family_sharing_expires_at.strftime('%b %d at %I:%M %p')
      end

      render json: response_data
    else
      render json: {
        success: false,
        message: 'Failed to update location sharing setting'
      }, status: :unprocessable_content
    end
  rescue => e
    render json: {
      success: false,
      message: 'An error occurred while updating location sharing'
    }, status: :internal_server_error
  end

  private

  def build_sharing_message(enabled, duration)
    return 'Location sharing disabled' unless enabled

    case duration
    when '1h'
      'Location sharing enabled for 1 hour'
    when '6h'
      'Location sharing enabled for 6 hours'
    when '12h'
      'Location sharing enabled for 12 hours'
    when '24h'
      'Location sharing enabled for 24 hours'
    when 'permanent', nil
      'Location sharing enabled'
    else
      duration.to_i > 0 ? "Location sharing enabled for #{duration.to_i} hours" : 'Location sharing enabled'
    end
  end

  def set_family
    @family = current_user.family
    redirect_to new_family_path, alert: 'You are not in a family' unless @family
  end

  def family_params
    params.require(:family).permit(:name)
  end
end
