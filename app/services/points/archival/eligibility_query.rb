# frozen_string_literal: true

module Points
  module Archival
    class EligibilityQuery
      def initialize(months: ENV.fetch('POINTS_ARCHIVAL_DORMANCY_MONTHS', 6).to_i)
        @cutoff = months.months.ago
      end

      def candidates
        return User.none if DawarichSettings.self_hosted?

        User.points_active
            .where('active_until IS NULL OR active_until < ?', Time.current)
            .where('last_sign_in_at IS NULL OR last_sign_in_at < ?', @cutoff)
            .where('points_count > 0')
      end
    end
  end
end
