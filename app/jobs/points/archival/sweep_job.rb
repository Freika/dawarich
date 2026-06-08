# frozen_string_literal: true

module Points
  module Archival
    class SweepJob < ApplicationJob
      queue_as :archival

      def perform
        EligibilityQuery.new.candidates.find_each do |user|
          ArchiveUserJob.perform_later(user.id)
        end
      end
    end
  end
end
