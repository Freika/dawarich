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

  it 'records monthly and yearly digest content and chart edge cases' do
    fixture = residual_digest_content
    expected = %w[
      monthly_km monthly_mi monthly_default monthly_de monthly_ambient_fr monthly_empty monthly_equal
      monthly_leap_invalid_days monthly_threshold monthly_nil_json monthly_negative monthly_malformed_distances
      monthly_malformed_locations monthly_malformed_visits monthly_invalid_month
      yearly_km yearly_mi yearly_default yearly_de yearly_ambient_fr yearly_empty yearly_shared
      yearly_sharing_disabled yearly_sparse_stats yearly_nil_json yearly_negative yearly_malformed_stats
    ]
    expect(fixture.fetch('cases').pluck('id')).to eq(expected)
    helpers = %w[
      hbar_empty hbar_zero hbar_half hbar_negative hbar_all_negative spark_empty spark_equal spark_negative_half
      heatmap_empty heatmap_quartiles heatmap_sparse_negative ranked_empty ranked_unicode_ties ranked_negative
      trend_equal trend_prior_zero trend_negative_half trend_positive_half trend_pct_nil
      trend_pct_minus100_zero trend_pct_minus100_positive
    ]
    expect(fixture.fetch('helpers').pluck('id')).to eq(helpers)
    assert_digest_content(fixture)
    fixture_bytes(residual_path('digest_content'), fixture)
  end

  it 'records digest staging and location request mail effects' do
    fixture = residual_mail_effects
    expected = %w[
      default inactive toggle_off legacy_off legacy_on explicit_off missing_digest missing_user deleted_user
      zero negative
      enqueue_failure save_failure smtp_failure sent clear_sent blank_fr invalid_fr changed_preference generation_locale
      missing_after_enqueue deleted_after_enqueue
    ].flat_map { |name| %w[monthly yearly].map { |period| "#{period}_#{name}" } }
    expect(fixture.fetch('digests').pluck('id')).to eq(expected)
    locations = %w[pending accepted expired missing_request missing_requester missing_target repeated cache_failure
                   enqueue_failure missing_after_enqueue]
    expect(fixture.fetch('locations').pluck('id')).to eq(locations)
    assert_mail_effects(fixture)
    fixture_bytes(residual_path('effects'), fixture)
  end

  context 'test mail HTTP capture', type: :request do
    it 'records test mail HTTP outcomes and retired mail no ops' do
      fixture = residual_mail_http
      expected = %w[
        html_success turbo_success guest cloud not_configured preferred_de query_locale body_locale
        socket_error timeout_error ssl_error system_error argument_error smtp_error
        smtp_fatal smtp_busy smtp_syntax smtp_auth_reply smtp_unknown smtp_multiline turbo_smtp_fatal
        unsafe_error turbo_error
        json_accept text_accept mixed_accept json_body malformed_json extra_body missing_csrf get_method head_method
        patch_method json_extension
      ]
      expect(fixture.fetch('cases').pluck('id')).to eq(expected)
      assert_mail_http(fixture)
      fixture_bytes(residual_path('http'), fixture)
    end
  end
end
