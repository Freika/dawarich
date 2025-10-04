# frozen_string_literal: true

class FamilyMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :set_family
  before_action :set_membership, only: %i[destroy]

  def destroy
    authorize @membership

    if @membership.owner?
      redirect_to family_path(@family),
                  alert: 'Family owners cannot remove their own membership. To leave the family, delete it instead.'
    else
      member_email = @membership.user.email
      @membership.destroy!
      redirect_to family_path(@family), notice: "#{member_email} has been removed from the family"
    end
  end

  private

  def ensure_family_feature_enabled!
    unless DawarichSettings.family_feature_enabled?
      redirect_to root_path, alert: 'Family feature is not available'
    end
  end

  def set_family
    @family = current_user.family

    redirect_to families_path, alert: 'Family not found' and return unless @family
  end

  def set_membership
    @membership = @family.family_memberships.find(params[:id])
  end
end
