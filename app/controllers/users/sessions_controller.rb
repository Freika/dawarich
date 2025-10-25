# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  before_action :load_invitation_context, only: [:new]

  def new
    super
  end

  private

  def load_invitation_context
    return unless invitation_token.present?

    @invitation = Family::Invitation.find_by(token: invitation_token)
    # Store token in session so it persists through the sign-in process
    session[:invitation_token] = invitation_token if invitation_token.present?
  end

  def invitation_token
    @invitation_token ||= params[:invitation_token] || session[:invitation_token]
  end
end
