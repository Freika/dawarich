# frozen_string_literal: true

# Removes flags for features that now ship unconditionally.
module FeatureFlags
  # Flags whose feature shipped unconditionally and no longer gates anything.
  RETIRED = %i[posters stay_point_detection instance_settings_resolver achievements poster_ordering].freeze

  def self.apply_defaults!
    RETIRED.each { |flag| Flipper.remove(flag) if Flipper.exist?(flag) }
  end
end
