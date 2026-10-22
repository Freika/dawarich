# frozen_string_literal: true

module Stats
  class ToponymsRefreshJob < ApplicationJob
    queue_as :stats

    def perform
      ToponymsRefresh.new.call
    end
  end
end
