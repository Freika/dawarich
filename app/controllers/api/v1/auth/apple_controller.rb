# frozen_string_literal: true

class Api::V1::Auth::AppleController < Api::V1::Auth::BaseController
  def create
    claims = Auth::VerifyAppleToken.new(params[:id_token]).call
  rescue Auth::VerifyAppleToken::InvalidToken => e
    return render_auth_error("Apple token verification failed: #{e.message}")
  else
    user, created = find_or_create_apple_user(claims)
    render_auth_success(user, status: created ? :created : :ok)
  end

  private

  def find_or_create_apple_user(claims)
    uid = claims[:sub]
    email = claims[:email].to_s.downcase

    user = User.find_by(provider: 'apple', uid: uid)
    return [user, false] if user

    # Match on email if the user already registered a different way
    user = User.find_by(email: email) if email.present?
    if user
      user.update!(provider: 'apple', uid: uid)
      return [user, false]
    end

    user = User.create!(
      email: email.presence || "#{uid}@apple.dawarich.app",
      password: SecureRandom.hex(32),
      provider: 'apple',
      uid: uid,
      status: :pending_payment,
      skip_auto_trial: true
    )
    [user, true]
  end
end
