# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  before_action :load_invitation_context, only: [:new]

  def new
    super
  end

  protected

  def after_sign_in_path_for(resource)
    # If there's an invitation token, redirect to the invitation page
    if invitation_token.present?
      invitation = FamilyInvitation.find_by(token: invitation_token)
      if invitation&.can_be_accepted?
        return family_invitation_path(invitation.token)
      end
    end

    super(resource)
  end

  private

  def load_invitation_context
    return unless invitation_token.present?

    @invitation = FamilyInvitation.find_by(token: invitation_token)
  end

  def invitation_token
    @invitation_token ||= params[:invitation_token] || session[:invitation_token]
  end
end