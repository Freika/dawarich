# frozen_string_literal: true

module Auth
  class FindOrCreateOauthUser
    class UnverifiedEmail < StandardError; end

    class LinkVerificationSent < StandardError
      attr_reader :user, :provider, :uid

      def initialize(user:, provider:, uid:)
        @user = user
        @provider = provider
        @uid = uid
        super('OAuth account link verification required for existing email')
      end
    end

    LINK_EMAIL_RATE_LIMIT_WINDOW = 1.hour
    LINK_EMAIL_RATE_LIMIT_KEY_PREFIX = 'oauth_account_link:rate_limit:'

    def initialize(provider:, provider_label:, claims:, email_verified:, on_email_collision: :send_email)
      @provider = provider
      @provider_label = provider_label
      @claims = claims
      @uid = claims[:sub].to_s
      @email = claims[:email].to_s.downcase
      @email_verified = email_verified
      @on_email_collision = on_email_collision
    end

    def call
      by_identity = User.find_by(provider: @provider, uid: @uid)
      return [by_identity, false] if by_identity

      if @email.present?
        existing = User.find_by(email: @email)
        return handle_email_collision(existing) if existing
      end

      [create_new_user, true]
    rescue ActiveRecord::RecordNotUnique
      retry_existing = @email.present? ? User.find_by(email: @email) : nil
      raise if retry_existing.nil?

      handle_email_collision(retry_existing)
    end

    private

    def handle_email_collision(existing)
      raise UnverifiedEmail unless @email_verified

      if auto_link_allowed?
        existing.update!(provider: @provider, uid: @uid)
        return [existing, false]
      end

      send_verification_email(existing) if @on_email_collision == :send_email
      raise LinkVerificationSent.new(user: existing, provider: @provider, uid: @uid)
    end

    def auto_link_allowed?
      false
    end

    def send_verification_email(existing_user)
      cache_key = "#{LINK_EMAIL_RATE_LIMIT_KEY_PREFIX}#{existing_user.id}"
      acquired = Rails.cache.write(
        cache_key, true,
        expires_in: LINK_EMAIL_RATE_LIMIT_WINDOW,
        unless_exist: true
      )
      return unless acquired

      token = Auth::IssueAccountLinkToken.new(
        existing_user, provider: @provider, uid: @uid
      ).call
      link_url = Rails.application.routes.url_helpers.auth_account_link_url(
        token: token,
        host: default_mailer_host,
        protocol: default_mailer_protocol
      )
      Users::MailerSendingJob.perform_later(
        existing_user.id,
        'oauth_account_link',
        provider_label: @provider_label,
        link_url: link_url
      )
    end

    def default_mailer_host
      ActionMailer::Base.default_url_options[:host] || ENV.fetch('APP_HOST', 'localhost')
    end

    def default_mailer_protocol
      ActionMailer::Base.default_url_options[:protocol] || 'https'
    end

    def create_new_user
      attrs = {
        email: @email.presence || "#{@uid}@#{@provider}.dawarich.app",
        password: SecureRandom.hex(32),
        provider: @provider,
        uid: @uid
      }
      attrs.merge!(status: :pending_payment, skip_auto_trial: true) unless DawarichSettings.self_hosted?

      User.create_or_find_by!(provider: @provider, uid: @uid) do |u|
        u.assign_attributes(attrs.except(:provider, :uid))
      end
    end
  end
end
