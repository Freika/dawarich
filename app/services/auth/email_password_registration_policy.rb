# frozen_string_literal: true

module Auth
  class EmailPasswordRegistrationPolicy
    def initialize(invitation_valid: false)
      @invitation_valid = invitation_valid
    end

    def allowed?
      return true unless DawarichSettings.self_hosted?
      return false if oidc_only?

      DawarichSettings.registration_enabled? || invitation_valid
    end

    def oidc_only?
      DawarichSettings.oidc_enabled? && !DawarichSettings.registration_enabled?
    end

    private

    attr_reader :invitation_valid
  end
end
