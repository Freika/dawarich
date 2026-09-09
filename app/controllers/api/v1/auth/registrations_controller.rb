# frozen_string_literal: true

class Api::V1::Auth::RegistrationsController < Api::V1::Auth::BaseController
  def create
    user = User.new(new_user_attrs)

    if user.save
      require_payment_from(user) unless accept_family_invitation(user)
      render_auth_success(user.reload, status: :created)
    else
      render json: {
        error: 'validation_failed',
        details: user.errors.as_json
      }, status: :unprocessable_content
    end
  end

  private

  def new_user_attrs
    base = {
      email: normalized_email,
      password: params[:password],
      password_confirmation: params[:password_confirmation]
    }
    return base if DawarichSettings.self_hosted?
    return base.merge(skip_auto_trial: true) if joining_family?

    base.merge(status: :pending_payment, skip_auto_trial: true)
  end

  def normalized_email
    params[:email]&.to_s&.downcase&.strip
  end

  def invitation
    return @invitation if defined?(@invitation)

    token = params[:invitation_token].to_s
    @invitation = token.present? ? Family::Invitation.find_by(token: token) : nil
  end

  def joining_family?
    invitation&.can_be_accepted? && invitation.email == normalized_email
  end

  def accept_family_invitation(user)
    return false unless joining_family?

    Families::AcceptInvitation.new(invitation: invitation, user: user).call
  end

  def require_payment_from(user)
    return if DawarichSettings.self_hosted?
    return if user.pending_payment?

    user.update!(status: :pending_payment)
  end
end
