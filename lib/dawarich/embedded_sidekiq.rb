# frozen_string_literal: true

module Dawarich
  module EmbeddedSidekiq
    class << self
      def enabled?
        ENV['SIDEKIQ_EMBEDDED'] == 'true'
      end

      def build
        Sidekiq.configure_embed do |config|
          config.concurrency = Integer(ENV.fetch('BACKGROUND_PROCESSING_CONCURRENCY', 2))
          settings = YAML.safe_load(ERB.new(Rails.root.join('config/sidekiq.yml').read).result,
                                    permitted_classes: [Symbol])
          config.queues = settings.fetch(:queues)
          config[:queues] = settings.fetch(:queues)
          require 'dawarich/idle_queue_check'
          selector = Sidekiq::LimitFetch::Global::Selector.singleton_class
          selector.prepend(Dawarich::IdleQueueCheck) unless selector < Dawarich::IdleQueueCheck
          configured = ENV['REVERSE_GEOCODING_CONCURRENCY'].presence&.to_i
          Sidekiq::Queue['reverse_geocoding'].limit = [configured || config.concurrency / 3, 1].max
        end
      end

      def start
        return if @instance

        @instance = build
        @instance.run
      end

      def stop
        Thread.new { @instance&.stop }.join
        @instance = nil
      end
    end
  end
end
