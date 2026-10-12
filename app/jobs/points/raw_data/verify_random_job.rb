# frozen_string_literal: true

module Points
  module RawData
    # Daily spot-check: verifies a random sample of archives.
    # Unverified archives get a chance to become clearable; already-verified
    # archives are re-checked for storage bit rot (failures alert via Sentry
    # without touching verified_at).
    class VerifyRandomJob < ApplicationJob
      queue_as :archival

      SAMPLE_SIZE = 10

      def perform
        archives = Points::RawDataArchive
                   .order(Arel.sql('RANDOM()'))
                   .limit(SAMPLE_SIZE)

        return if archives.empty?

        verifier = Verifier.new

        archives.each do |archive|
          verifier.verify_specific_archive(archive.id)
        end
      rescue StandardError => e
        ExceptionReporter.call(e, 'Archive verification spot-check failed')
        raise
      end
    end
  end
end
