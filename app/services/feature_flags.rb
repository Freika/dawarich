# frozen_string_literal: true

# Keeps the Flipper store in step with the flags the code actually reads, so a
# flag appears in the admin UI on both fresh installs and upgrades.
module FeatureFlags
  # Flags the code reads, mapped to the state a brand-new install starts in.
  # An existing flag is never touched, so an instance that switched one off
  # keeps it off.
  # instance_settings_resolver gates the DB-backed settings path. It ships off:
  # until an operator turns it on, geocoding resolves from the ENV constants
  # exactly as it always has, so the switch is the rollback for that change.
  DEFAULTS = { poster_ordering: true, instance_settings_resolver: false }.freeze

  # Flags whose feature shipped unconditionally and no longer gates anything.
  RETIRED = %i[posters stay_point_detection].freeze

  def self.apply_defaults!
    DEFAULTS.each do |flag, enabled|
      next if Flipper.exist?(flag)

      Flipper.add(flag)
      Flipper.enable(flag) if enabled
    end

    RETIRED.each { |flag| Flipper.remove(flag) if Flipper.exist?(flag) }
  end
end
