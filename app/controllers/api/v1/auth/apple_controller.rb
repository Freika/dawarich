# frozen_string_literal: true

class Api::V1::Auth::AppleController < Api::V1::Auth::BaseController
  class UnverifiedEmail < StandardError; end

  def create
    claims =
      begin
        Auth::VerifyAppleToken.new(params[:id_token]).call
      rescue Auth::VerifyAppleToken::InvalidToken => e
        return render_auth_error("Apple token verification failed: #{e.message}")
      end

    user, created = find_or_create_apple_user(claims)
    render_auth_success(user, status: created ? :created : :ok)
  rescue UnverifiedEmail
    render json: {
      error: 'email_not_verified',
      message: 'Apple has not verified this email. Sign in with password and link from settings.'
    }, status: :forbidden
  end

  private

  def find_or_create_apple_user(claims)
    uid = claims[:sub]
    email = claims[:email].to_s.downcase
    # Apple sends email_verified as a string 'true'/'false' in id_tokens
    email_verified = [true, 'true'].include?(claims[:email_verified])

    User.transaction do
      user = User.find_by(provider: 'apple', uid: uid)
      return [user, false] if user

      # Match on email if the user already registered a different way.
      # SECURITY: only link if Apple asserts the email is verified.
      if email.present?
        existing_by_email = User.find_by(email: email)
        if existing_by_email
          raise UnverifiedEmail unless email_verified

          existing_by_email.update!(provider: 'apple', uid: uid)
          return [existing_by_email, false]
        end
      end

      attrs = {
        email: email.presence || "#{uid}@apple.dawarich.app",
        password: SecureRandom.hex(32),
        provider: 'apple',
        uid: uid
      }

      user =
        if DawarichSettings.self_hosted?
          User.where(provider: 'apple', uid: uid).first_or_create!(attrs)
        else
          User.where(provider: 'apple', uid: uid)
              .first_or_create!(attrs.merge(status: :pending_payment, skip_auto_trial: true))
        end

      [user, true]
    end
  end
end
