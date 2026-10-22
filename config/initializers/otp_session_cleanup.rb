# frozen_string_literal: true

Warden::Manager.after_set_user do |_user, auth, options|
  next unless options[:scope] == :user

  %w[otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me].each do |key|
    auth.raw_session.delete(key)
  end
end
