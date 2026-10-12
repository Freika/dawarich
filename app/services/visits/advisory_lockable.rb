# frozen_string_literal: true

module Visits
  module AdvisoryLockable
    private

    def advisory_locks_enabled?
      ActiveRecord::Base.connection_pool.db_config.configuration_hash[:advisory_locks] != false
    end
  end
end
