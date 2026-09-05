# frozen_string_literal: true

module TeslaMate
  class SyncJob < ApplicationJob
    queue_as :imports
    sidekiq_options retry: false

    retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
      job.report_failure(error)
    end

    def perform(user_id)
      user = find_user_or_skip(user_id) || return
      return unless sync_allowed?(user)

      ActiveRecord::Base.with_advisory_lock("teslamate-sync:#{user.id}", timeout_seconds: 0) do
        TeslaMate::Sync.new(user).call
      end
    end

    def report_failure(error)
      user_id = arguments.first
      user = User.find_by(id: user_id)

      ExceptionReporter.call(error, "TeslaMateApi sync failed for user #{user_id}")
      notify_sync_failed(user, error) if user
    end

    private

    def sync_allowed?(user)
      return true if DawarichSettings.self_hosted?

      user.active_until&.future? &&
        user.entitlements.integrations? &&
        !PointsLimitExceeded.new(user).call
    end

    def notify_sync_failed(user, error)
      I18n.with_locale(user.locale) do
        Notifications::Create.new(
          user: user,
          title: I18n.t('jobs.tesla_mate.sync_job.teslamate_sync_failed'),
          content: I18n.t('jobs.tesla_mate.sync_job.your_teslamate_sync_failed', message: error.message),
          kind: :error
        ).call
      end
    end
  end
end
