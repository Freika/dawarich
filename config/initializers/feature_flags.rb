# frozen_string_literal: true

# Register feature flags so they appear in the Flipper admin UI for both fresh
# installs and existing instances on upgrade. Rescued so boot never fails when
# the Flipper tables aren't present yet (e.g. during `db:migrate` on a
# brand-new database).
Rails.application.config.after_initialize do
  FeatureFlags.apply_defaults!
rescue StandardError => e
  Rails.logger.warn("[feature_flags] could not register flags: #{e.class}: #{e.message}")
end
