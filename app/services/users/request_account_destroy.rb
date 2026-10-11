# frozen_string_literal: true

module Users
  class RequestAccountDestroy
    RATE_LIMIT_WINDOW = 1.hour
    RATE_LIMIT_KEY_PREFIX = 'account_destroy:rate_limit:'

    Result = Struct.new(:status, :message, keyword_init: true)

    SENT_MESSAGE = 'A confirmation email has been sent. Click the link in the email to permanently ' \
                   'delete your account.'
    THROTTLED_MESSAGE = 'A confirmation email was already sent recently. Check your inbox or wait ' \
                        'an hour before requesting another one.'

    def initialize(user, host:, protocol:)
      @user = user
      @host = host
      @protocol = protocol
    end

    def call
      ActiveRecord::Base.with_advisory_lock("account_destroy:request:#{@user.id}") do
        request_confirmation
      end
    end

    private

    def request_confirmation
      acquired = acquire_rate_limit_slot
      return Result.new(status: :throttled, message: THROTTLED_MESSAGE) unless acquired

      token = Users::IssueDestroyToken.new(@user).call
      link_url = Rails.application.routes.url_helpers.user_destroy_confirmation_url(
        token: token, host: @host, protocol: @protocol
      )

      job = Users::MailerSendingJob.perform_later(
        @user.id,
        'account_destroy_confirmation',
        link_url: link_url
      )
      unless job.try(:successfully_enqueued?)
        raise ActiveJob::EnqueueError, 'Account deletion confirmation could not be queued'
      end

      Result.new(status: :sent, message: SENT_MESSAGE)
    rescue StandardError
      Rails.cache.delete(rate_limit_key) if acquired
      raise
    end

    def acquire_rate_limit_slot
      Rails.cache.write(
        rate_limit_key,
        true,
        expires_in: RATE_LIMIT_WINDOW,
        unless_exist: true
      )
    end

    def rate_limit_key
      "#{RATE_LIMIT_KEY_PREFIX}#{@user.id}"
    end
  end
end
