# frozen_string_literal: true

class Api::V1::Auth::GoogleController < Api::V1::Auth::BaseController
  def create
    claims = Auth::VerifyGoogleToken.new(params[:id_token]).call
  rescue Auth::VerifyGoogleToken::InvalidToken => e
    return render_auth_error("Google token verification failed: #{e.message}")
  else
    user, created = find_or_create_google_user(claims)
    render_auth_success(user, status: created ? :created : :ok)
  end

  private

  def find_or_create_google_user(claims)
    uid = claims[:sub]
    email = claims[:email].to_s.downcase

    user = User.find_by(provider: 'google', uid: uid)
    return [user, false] if user

    # Match on email if the user already registered a different way
    user = User.find_by(email: email) if email.present?
    if user
      user.update!(provider: 'google', uid: uid)
      return [user, false]
    end

    attrs = {
      email: email.presence || "#{uid}@google.dawarich.app",
      password: SecureRandom.hex(32),
      provider: 'google',
      uid: uid
    }

    if DawarichSettings.self_hosted?
      user = User.create!(attrs)
    else
      user = User.create!(attrs.merge(status: :pending_payment, skip_auto_trial: true))
    end

    [user, true]
  end
end
