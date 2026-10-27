# frozen_string_literal: true

# Signing in from a family invitation joins the family straight away, the same
# as signing up from one does (Users::RegistrationsController).
module PendingInvitationAcceptable
  extend ActiveSupport::Concern

  private

  # Where to send a user who just signed in with an invitation waiting, or nil
  # to carry on with the usual after-sign-in path.
  def pending_invitation_path_for(user)
    # The sign-in form posts an empty invitation_token when the invitation
    # came from the session, so a blank param must not hide the session one.
    token = params[:invitation_token].presence || session[:invitation_token]
    return if token.blank?

    invitation = Family::Invitation.find_by(token: token)
    return unless invitation&.can_be_accepted?
    return family_invitation_path(invitation.token) unless signing_in_now?

    service = Families::AcceptInvitation.new(invitation: invitation, user: user)
    unless service.call
      Rails.logger.info("Family invitation #{invitation.id} not accepted on sign-in: #{service.error_message}")
      flash[:alert] = service.error_message
      return family_invitation_path(invitation.token)
    end

    session.delete(:invitation_token)
    # Joining can lift the user's own plan state (e.g. out of pending_payment),
    # which the rest of after_sign_in_path_for reads.
    user.reload
    flash[:notice] = I18n.t('controllers.users.registrations.welcome_to_name_you_re_now_part_of_the_family',
                            name: invitation.family.name)
    family_path unless mobile_client?
  end

  # Devise also asks for the after-sign-in path when someone already signed in
  # merely opens the sign-in or sign-up page. Only a real sign-in (a form POST
  # or an OmniAuth callback) may join a family; otherwise a link alone would.
  def signing_in_now?
    !request.get? || request.env['omniauth.auth'].present?
  end
end
