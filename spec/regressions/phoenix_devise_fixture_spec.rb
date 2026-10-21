# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix port: the Rails settings pinned in the Phoenix cookie fixture' do
  include ActiveSupport::Testing::TimeHelpers

  let(:fixture) { JSON.parse(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json').read) }

  it 'matches the live Devise settings Phoenix reimplements' do
    live = {
      'remember_for_seconds' => User.remember_for.to_i,
      'lockable' => User.devise_modules.include?(:lockable),
      'lock_strategy' => User.lock_strategy.to_s,
      'unlock_strategy' => User.unlock_strategy.to_s,
      'time_unlock' => User.unlock_strategy_enabled?(:time),
      'unlock_in_seconds' => User.unlock_in.to_i
    }

    expect(live).to eq(fixture.slice(*live.keys))
  end

  it 'reads the fixture cookies with the live cookie settings Phoenix reimplements' do
    env = Rails.application.env_config.merge(
      'action_dispatch.secret_key_base' => fixture['rails_test_secret'],
      'action_dispatch.key_generator' => Rails.application.key_generator(fixture['rails_test_secret']),
      'HTTP_COOKIE' => "_dawarich_session=#{fixture['session_cookie']}; " \
                       "remember_user_token=#{fixture['remember_cookie']}"
    )

    travel_to Time.iso8601(fixture['now']) do
      jar = ActionDispatch::Request.new(env).cookie_jar
      expect(jar.encrypted['_dawarich_session']).to eq(fixture['expected_session'])
      expect(jar.signed['remember_user_token']).to eq(fixture['expected_remember'])
    end
  end
end
