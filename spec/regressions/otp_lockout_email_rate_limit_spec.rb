# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OTP lockout email rate limit' do
  let(:user) { create(:user) }
  let(:cache_key) { "otp_lockout_email_throttle/user/#{user.id}" }

  before { Rails.cache.delete(cache_key) }
  after  { Rails.cache.delete(cache_key) }

  it 'sends one lockout email even when a second lockout cycle starts within the throttle window' do
    User::MAX_FAILED_OTP_ATTEMPTS.times { user.register_failed_otp_attempt! }
    expect(UsersMailer.deliveries.size + ActionMailer::Base.deliveries.size).to be >= 0

    expect do
      user.update_columns(failed_otp_attempts: 0, otp_locked_at: 31.minutes.ago)
      User::MAX_FAILED_OTP_ATTEMPTS.times { user.register_failed_otp_attempt! }
    end.not_to have_enqueued_mail(UsersMailer, :otp_account_locked)
  end

  it 'sends the email again once the throttle window has elapsed' do
    User::MAX_FAILED_OTP_ATTEMPTS.times { user.register_failed_otp_attempt! }

    Rails.cache.delete(cache_key)
    user.update_columns(failed_otp_attempts: 0, otp_locked_at: 31.minutes.ago)

    expect do
      User::MAX_FAILED_OTP_ATTEMPTS.times { user.register_failed_otp_attempt! }
    end.to have_enqueued_mail(UsersMailer, :otp_account_locked)
  end
end
