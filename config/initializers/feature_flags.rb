# frozen_string_literal: true

# Register feature flags so they appear in the Flipper admin UI for both fresh
# installs and existing instances on upgrade. Guarded with `exist?` so it only
# writes when missing, and rescued so boot never fails when the Flipper tables
# aren't present yet (e.g. during `db:migrate` on a brand-new database).
Rails.application.config.after_initialize do
  Flipper.add(:stay_point_detection) unless Flipper.exist?(:stay_point_detection)
rescue StandardError => e
  Rails.logger.warn("[feature_flags] could not register flags: #{e.class}: #{e.message}")
end
