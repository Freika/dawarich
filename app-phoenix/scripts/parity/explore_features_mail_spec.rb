# frozen_string_literal: true

require 'rails_helper'
require_relative 'residual_mail_fixture_support'

RSpec.describe 'Phoenix fixture: the explore_features mail as Rails renders it' do
  include ResidualMailFixtureSupport
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to(Time.utc(2026, 10, 4, 12)) { example.run }
  end

  it 'records the subject and both bodies for preferred locales and for the job-locale fallback' do
    cases = { 'en' => [{ 'locale' => 'en' }, :en], 'de' => [{ 'locale' => ' DE ' }, :en], 'fallback_fr' => [{}, :fr] }

    fixtures = cases.to_h do |name, (settings, job_locale)|
      user = create(:user, email: "mail-#{name}@example.test")
      user.update_columns(settings: user.settings.except('locale').merge(settings))
      message = I18n.with_locale(job_locale) { UsersMailer.with(user: user.reload).explore_features.message }

      [name, { 'email' => user.email, 'settings' => settings, 'job_locale' => job_locale.to_s,
               'subject' => message.subject, 'text' => message.text_part.body.decoded,
               'html' => message.html_part.body.decoded }]
    end

    path = Rails.root.join('app-phoenix/test/fixtures/mail/explore_features.json')
    fixture_bytes(path, fixtures)
  end

  it 'records reachable residual and Devise mail contracts without delivery' do
    fixture = residual_content
    expected = %w[
      otp_account_locked_en otp_account_locked_de otp_account_locked_fallback_fr
      test_email_en test_email_de test_email_fallback_fr test_email_berlin test_email_invalid_zone
      location_request_en location_request_de location_request_fallback_fr
      reset_password_instructions_en reset_password_instructions_de reset_password_instructions_fallback_fr
      unlock_instructions_en unlock_instructions_de unlock_instructions_fallback_fr
      email_changed_current_en email_changed_current_de email_changed_current_fallback_fr
      password_change_en password_change_de password_change_fallback_fr
    ]
    expect(fixture.fetch('cases').pluck('id')).to eq(expected)
    assert_content(fixture)
    fixture_bytes(residual_path('content'), fixture)
  end

  it 'records Rails auth trigger recipients locale and suppressed notification intents' do
    fixture = residual_auth_intents
    expected = %w[
      email_changed_preferred email_changed_ambient email_unchanged email_flag_off email_skipped
      password_changed_preferred password_changed_ambient password_unchanged password_flag_off password_skipped
      email_delivery_failure otp_below_threshold otp_at_threshold otp_already_locked otp_throttled otp_throttle_cleared
      otp_enqueue_failure
    ]
    expect(fixture.fetch('cases').pluck('id')).to eq(expected)
    assert_auth_intents(fixture)
    fixture_bytes(residual_path('auth_intents'), fixture)
  end
end
