# frozen_string_literal: true

module Exploration
  # Reads every source table from one database snapshot, so a result never mixes
  # evidence from before and after a concurrent write. Writes committed after the
  # snapshot starts stay dirty for the next run.
  module SourceSnapshot
    ATTEMPTS = 3

    def self.call(&)
      attempt = 0
      begin
        ApplicationRecord.transaction(isolation: :repeatable_read, &)
      rescue ActiveRecord::SerializationFailure
        attempt += 1
        retry if attempt < ATTEMPTS
        raise
      end
    end
  end
end
