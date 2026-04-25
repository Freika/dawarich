# frozen_string_literal: true

module Auth
  # Shared logic behind Api::V1::Auth::AppleController and ::GoogleController.
  #
  # Three branches:
  #
  #   1. Existing user with this (provider, uid) → return it.
  #   2. New identity whose email matches an existing account:
  #        - Without email_verified: refuse (UnverifiedEmail).
  #        - With email_verified (default, secure path): issue a signed
  #          15-minute account-link JWT, email it to the registered
  #          address, and raise LinkVerificationSent so the controller
  #          returns 202.
  #   3. New identity, new email: create the user.
  #
  # Silent email-based linking is a known OAuth account-takeover primitive
  # when an attacker controls an OAuth identity on an email the victim also
  # used for Dawarich. The default (secure) behavior is to require email
  # click-through proof of control over the registered email.
  #
  # NOTE (PR-A): A future PR-B reintroduces a Flipper-backed feature flag
  # (`oauth_auto_link_verified_email`) that opts into the legacy permissive
  # auto-link path. Until that flag exists, `auto_link_allowed?` returns
  # `true` ONLY IF you choose to enable it; here we keep the safe default
  # (`false`) so every email-collision flow goes through the email-verified
  # link-token path.
  class FindOrCreateOauthUser
    def initialize(provider:, provider_label:, claims:, email_verified:)
      @provider = provider
      @provider_label = provider_label
      @claims = claims
      @uid = claims[:sub].to_s
      @email = claims[:email].to_s.downcase
      @email_verified = email_verified
    end

    def call
      # Resolve without wrapping the whole method in a transaction — `return`
      # out of a transaction block triggers a rollback warning in Rails 7.2+
      # and the paths below only issue single writes (update! or create!),
      # each atomic on its own.
      by_identity = User.find_by(provider: @provider, uid: @uid)
      return [by_identity, false] if by_identity

      if @email.present?
        existing = User.find_by(email: @email)
        return handle_email_collision(existing) if existing
      end

      [create_new_user, true]
    end

    private

    # Returns a [user, created] tuple on the "silent auto-link" path, or
    # raises a controller-scoped error to short-circuit the response.
    def handle_email_collision(existing)
      raise controller_error(:UnverifiedEmail) unless @email_verified

      if auto_link_allowed?
        existing.update!(provider: @provider, uid: @uid)
        return [existing, false]
      end

      send_verification_email(existing)
      raise controller_error(:LinkVerificationSent)
    end

    # PR-A: Flipper is not yet wired in; default to the safe path (require
    # email click-through verification). PR-B will reintroduce a Flipper
    # check on `:oauth_auto_link_verified_email` to opt back into the
    # legacy permissive flow when the operator explicitly enables it.
    def auto_link_allowed?
      false
    end

    def send_verification_email(existing_user)
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

      # create_or_find_by! handles the cross-request race on (provider, uid)
      # via the partial unique index: if a concurrent request inserted first,
      # we re-fetch that row without blowing up.
      User.create_or_find_by!(provider: @provider, uid: @uid) do |u|
        u.assign_attributes(attrs.except(:provider, :uid))
      end
    end

    def controller_error(name)
      controller_klass = {
        'apple'  => Api::V1::Auth::AppleController,
        'google' => Api::V1::Auth::GoogleController
      }.fetch(@provider)
      controller_klass.const_get(name)
    end
  end
end
