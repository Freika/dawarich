# frozen_string_literal: true

module Points
  module RawData
    # Daily spot-check: verifies a random sample of unverified archives.
    # Uses the existing Verifier which checks checksums, counts, and sampled raw_data matches.
    class VerifyRandomJob < ApplicationJob
      queue_as :archival

      SAMPLE_SIZE = 10

      def perform
        archives = Points::RawDataArchive
                   .where(verified_at: nil)
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
