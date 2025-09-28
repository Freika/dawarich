# frozen_string_literal: true

class FamiliesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :set_family, only: %i[show edit update destroy leave]

  def index
    redirect_to family_path(current_user.family) if current_user.in_family?
  end

  def show
    authorize @family

    # Use optimized family methods for better performance
    @members = @family.members.includes(:family_membership).order(:email)
    @pending_invitations = @family.active_invitations.order(:created_at)

    # Use cached counts to avoid extra queries
    @member_count = @family.member_count
    @can_invite = @family.can_add_members?
  end

  def new
    redirect_to family_path(current_user.family) if current_user.in_family?

    @family = Family.new
  end

  def create
    service = Families::Create.new(
      user: current_user,
      name: family_params[:name]
    )

    if service.call
      redirect_to family_path(service.family), notice: 'Family created successfully!'
    else
      @family = Family.new(family_params)

      # Handle validation errors
      if service.errors.any?
        service.errors.each do |attribute, message|
          @family.errors.add(attribute, message)
        end
      end

      # Handle service-level errors
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
      redirect_to family_path(@family), notice: 'Family updated successfully!'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    authorize @family

    if @family.members.count > 1
      redirect_to family_path(@family), alert: 'Cannot delete family with members. Remove all members first.'
    else
      @family.destroy
      redirect_to families_path, notice: 'Family deleted successfully!'
    end
  end

  def leave
    authorize @family, :leave?

    service = Families::Leave.new(user: current_user)

    if service.call
      redirect_to families_path, notice: 'You have left the family'
    else
      redirect_to family_path(@family), alert: service.error_message || 'Cannot leave family.'
    end
  rescue Pundit::NotAuthorizedError
    # Handle case where owner with members tries to leave
    redirect_to family_path(@family),
                alert: 'You cannot leave the family while you are the owner and there are other members. Remove all members first or transfer ownership.'
  end

  private

  def ensure_family_feature_enabled!
    unless DawarichSettings.family_feature_enabled?
      redirect_to root_path, alert: 'Family feature is not available'
    end
  end

  def set_family
    @family = current_user.family
    redirect_to families_path unless @family
  end

  def family_params
    params.require(:family).permit(:name)
  end
end
