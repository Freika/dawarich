# frozen_string_literal: true

# Jobs enqueued by 1.21.0 under the old name still run after an upgrade.
class DataMigrations::BackfillKmlVelocitiesJob < DataMigrations::BackfillMissingVelocitiesJob
end
