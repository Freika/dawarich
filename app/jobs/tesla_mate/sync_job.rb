# frozen_string_literal: true

module TeslaMate
  class SyncJob < ApplicationJob
    queue_as :imports

    def perform(user_id)
      user = find_user_or_skip(user_id) || return

      TeslaMate::Sync.new(user).call
    rescue TeslaMate::Client::Error => e
      ExceptionReporter.call(e, "TeslaMateApi sync failed for user #{user_id}")
      notify_sync_failed(user, e)

      raise e
    end

    private

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
