# frozen_string_literal: true

class FamiliesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_family, only: %i[show edit update destroy leave]

  def index
    redirect_to family_path(current_user.family) if current_user.in_family?
  end

  def show
    authorize @family

    @members = @family.members.includes(:family_membership)
    @pending_invitations = @family.family_invitations.active
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

      service.errors.each do |attribute, message|
        @family.errors.add(attribute, message)
      end
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

  def set_family
    @family = current_user.family
    redirect_to families_path unless @family
  end

  def family_params
    params.require(:family).permit(:name)
  end
end
