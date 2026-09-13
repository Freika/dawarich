# frozen_string_literal: true

module Auth
  class EmailPasswordRegistrationPolicy
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

    private

    attr_reader :invitation, :email

    def normalize(value)
      value.to_s.downcase.strip
    end
  end
end
