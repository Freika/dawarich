# frozen_string_literal: true

# A 2FA-enabled account must clear its second factor on every web sign-in.
# Instead of signing in, stage the same session handshake that
# Users::OtpChallengeController consumes and show the code form.
module OtpChallengeStaging
  extend ActiveSupport::Concern

  private

  def otp_challenge_required?(user)
    DawarichSettings.two_factor_available? && user.otp_required_for_login?
  end

  def stage_otp_challenge(user)
    session[:otp_user_id] = user.id
    session[:otp_challenge_at] = Time.current.to_i
    # Remember-me belongs to a password sign-in; an abandoned one must not carry over.
    session.delete(:otp_remember_me)
    render 'devise/sessions/otp_challenge', status: :unprocessable_entity
  end
end
