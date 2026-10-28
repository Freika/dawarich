# frozen_string_literal: true

module Achievements
  class PrivacyFingerprint
    def self.call(user)
      zones = Users::PrivacyZones.new(user).call.sort_by { |zone| [zone[:place_id], zone[:radius]] }
      Digest::SHA256.hexdigest(zones.to_json)
    end
  end
end
