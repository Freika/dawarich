# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: the cookies Rails issues at sign-in', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }

  def set_cookie_value(response, name)
    Array(response.headers['Set-Cookie']).flat_map { |line| line.split("\n") }
                                         .find { |line| line.start_with?("#{name}=") }
                                         &.split(';')&.first&.delete_prefix("#{name}=")
  end

  def jar(cookies)
    ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_COOKIE' => cookies)).cookie_jar
  end

  def remembered_user(value)
    User.serialize_from_cookie(*jar("remember_user_token=#{value}").signed['remember_user_token'])
  end

  it 'writes app-phoenix/test/fixtures/rails_cookies.json' do
    expect(Rails.application.secret_key_base).to eq(secret)

    travel_to Time.utc(2026, 9, 26, 12, 0, 0) do
      password = 'phoenix-fixture-password'
      user = create(:user, email: 'phoenix-cookies@dawarich.test', password: password, password_confirmation: password)
      user.update_columns(remember_created_at: 1.minute.ago)

      post user_session_path, params: { user: { email: user.email, password: password, remember_me: '1' } }
      expect(response).to have_http_status(:redirect)
      session_value = set_cookie_value(response, '_dawarich_session')
      remember_value = set_cookie_value(response, 'remember_user_token')
      expect([session_value, remember_value]).to all(be_present)
      expect(remembered_user(remember_value)).to eq(user)

      other = jar('')
      other.encrypted['shared_link_1'] = 'unlocked'
      other_value = Rack::Utils.escape(other['shared_link_1'])

      previous_forgery_protection = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        get '/notifications'
      ensure
        ActionController::Base.allow_forgery_protection = previous_forgery_protection
      end
      expect(response).to have_http_status(:ok)
      csrf_session = set_cookie_value(response, '_dawarich_session') || session_value
      masked = response.body[/<meta name="csrf-token" content="([^"]+)"/, 1]
      expect(masked).to be_present

      other_user = create(:user, email: 'phoenix-cookies-other@dawarich.test', password: password,
                                 password_confirmation: password)
      other_user.update_columns(remember_created_at: 1.minute.ago)
      reset!
      post user_session_path, params: { user: { email: other_user.email, password: password, remember_me: '1' } }
      expect(response).to have_http_status(:redirect)
      other_remember_value = set_cookie_value(response, 'remember_user_token')
      expect(remembered_user(other_remember_value)).to eq(other_user)

      signed_in = jar("_dawarich_session=#{session_value}; remember_user_token=#{remember_value}")
      user.reload
      other_user.reload
      fixture = {
        rails_test_secret: secret,
        now: Time.current.utc.iso8601(6),
        remember_for_seconds: User.remember_for.to_i,
        lockable: User.devise_modules.include?(:lockable),
        lock_strategy: User.lock_strategy.to_s,
        unlock_strategy: User.unlock_strategy.to_s,
        time_unlock: User.unlock_strategy_enabled?(:time),
        unlock_in_seconds: User.unlock_in.to_i,
        user: { id: user.id, email: user.email, encrypted_password: user.encrypted_password,
                remember_created_at: user.remember_created_at.utc.iso8601(6) },
        other_user: { id: other_user.id, email: other_user.email, encrypted_password: other_user.encrypted_password,
                      remember_created_at: other_user.remember_created_at.utc.iso8601(6) },
        other_remember_cookie: other_remember_value,
        session_cookie: session_value,
        remember_cookie: remember_value,
        other_purpose_cookie: other_value,
        expected_session: signed_in.encrypted['_dawarich_session'],
        expected_remember: signed_in.signed['remember_user_token'],
        csrf: { session_cookie: csrf_session, masked_token: masked }
      }
      File.write(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json'), "#{JSON.pretty_generate(fixture)}\n")
    end
  end
end
