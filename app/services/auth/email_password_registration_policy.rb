# frozen_string_literal: true

module Auth
  class EmailPasswordRegistrationPolicy
    OIDC_ONLY_MESSAGE_KEY =
      'controllers.users.registrations.email_password_registration_is_disabled_please_use_oidc_to_sign'
    INVITATION_EMAIL_MISMATCH_MESSAGE_KEY =
      'services.families.accept_invitation.this_invitation_is_not_for_your_email_address'
    UNAVAILABLE_MESSAGE_KEY =
      'controllers.users.registrations.registration_is_not_available_please_contact_your_administrator_for_acce'

    def initialize(invitation: nil, email: nil)
      @invitation = invitation
      @email = email
    end

    def allowed?
      return true unless DawarichSettings.self_hosted?
      return false if oidc_only?

      DawarichSettings.registration_enabled? || invitation_matches_email?
    end

    def oidc_only?
      DawarichSettings.oidc_enabled? && !DawarichSettings.registration_enabled?
    end

    def invitation_matches_email?
      return false unless invitation&.can_be_accepted?

      normalize(invitation.email) == normalize(email)
    end

    def denial_message_key
      return OIDC_ONLY_MESSAGE_KEY if oidc_only?
      return INVITATION_EMAIL_MISMATCH_MESSAGE_KEY if invitation&.can_be_accepted? && !invitation_matches_email?

      UNAVAILABLE_MESSAGE_KEY
    end

    private

    attr_reader :invitation, :email

    def normalize(value)
      value.to_s.downcase.strip
    end
  end
end
