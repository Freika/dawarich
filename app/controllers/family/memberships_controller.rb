# frozen_string_literal: true

class Family::MembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_family_feature_enabled!
  before_action :set_family
  before_action :set_membership, only: %i[destroy]

  def destroy
    authorize @membership

    member_user = @membership.user
    service = Families::Memberships::Destroy.new(user: current_user, member_to_remove: member_user)

    if service.call
      if member_user == current_user
        # User removed themselves
        redirect_to new_family_path, notice: 'You have left the family'
      else
        # Owner removed another member
        redirect_to family_path, notice: "#{member_user.email} has been removed from the family"
      end
    else
      redirect_to family_path, alert: service.error_message || 'Failed to remove member'
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

    redirect_to new_family_path, alert: 'You are not in a family' and return unless @family
  end

  def set_membership
    @membership = @family.family_memberships.find(params[:id])
  end
end
