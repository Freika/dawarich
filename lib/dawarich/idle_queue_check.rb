# frozen_string_literal: true

module Dawarich
  # Avoid limit_fetch's per-queue lock writes when there is no work to reserve.
  # Returning no queues uses its normal idle sleep (at most two seconds before
  # checking again). Once work exists, its normal atomic limits still apply.
  module IdleQueueCheck
    def acquire(queues, namespace)
      return [] if queues.empty?

      keys = queues.map { |queue| "#{namespace}queue:#{queue}" }
      return [] if Sidekiq.redis { |connection| connection.exists(*keys) }.zero?

      super
    end
  end
end
