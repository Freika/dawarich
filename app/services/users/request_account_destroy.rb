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
      return Result.new(status: :throttled, message: THROTTLED_MESSAGE) unless acquire_rate_limit_slot

      token = Users::IssueDestroyToken.new(@user).call
      link_url = Rails.application.routes.url_helpers.user_destroy_confirmation_url(
        token: token, host: @host, protocol: @protocol
      )

      Users::MailerSendingJob.perform_later(
        @user.id,
        'account_destroy_confirmation',
        link_url: link_url
      )

      Result.new(status: :sent, message: SENT_MESSAGE)
    end

    private

    def acquire_rate_limit_slot
      Rails.cache.write(
        "#{RATE_LIMIT_KEY_PREFIX}#{@user.id}",
        true,
        expires_in: RATE_LIMIT_WINDOW,
        unless_exist: true
      )
    end
  end
end
