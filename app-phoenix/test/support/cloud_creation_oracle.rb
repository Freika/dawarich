# frozen_string_literal: true

require 'rspec/mocks/standalone'
require 'active_support/testing/time_helpers'
clock_helper = Object.new.extend(ActiveSupport::Testing::TimeHelpers)

Rails.logger = ActiveSupport::Logger.new(File::NULL)
ActiveRecord::Base.logger = nil
observations = []
RSpec::Mocks.with_temporary_scope do
  allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  allow(Users::CreationWebhookJob).to receive(:perform_later)
  allow(UserMailCommands).to receive(:produce)
  allow(JobCommands).to receive(:produce)
  allow(HTTParty).to receive(:post).and_return(nil)
  ['2026-03-27T12:00:00Z', '2028-02-29T12:00:00Z'].each do |clock|
    Time.use_zone('Europe/Berlin') do
      clock_helper.travel_to(Time.iso8601(clock)) do
        I18n.with_locale(:de) do
          user = User.create!(email: "l1-oracle-#{SecureRandom.hex(8)}@example.invalid", password: 'synthetic-password')
          observations << { now: clock, status: user.reload.status, plan: user.plan,
                            active_until: user.active_until.utc.iso8601,
                            explore_at: 2.days.from_now.utc.iso8601, locale: I18n.locale.to_s,
                            key_valid: user.api_key.match?(/\A[0-9a-f]{64}\z/) }
          user.delete
        end
      end
    end
  end
  user = User.new(email: "l1-oracle-#{SecureRandom.hex(8)}@example.invalid", password: 'synthetic-password',
                  status: :pending_payment, active_until: Time.utc(2030))
  user.skip_auto_trial = true
  user.save!
  skip = { status: user.reload.status, active_until: user.active_until.utc.iso8601,
           key_valid: user.api_key.match?(/\A[0-9a-f]{64}\z/) }
  payload = nil
  allow(HTTParty).to receive(:post) do |_url, options|
    payload = JWT.decode(JSON.parse(options[:body]).fetch('token'), 'synthetic-oracle-key', true,
                         algorithm: 'HS256').first.except('user_id', 'email')
  end
  user.update_columns(first_name: 'Ada', last_name: 'Lovelace', status: 2, active_until: Time.utc(2026, 10, 6, 12))
  user.reload
  previous = ENV.to_h.slice('MANAGER_URL', 'JWT_SECRET_KEY')
  begin
    ENV['MANAGER_URL'] = 'https://manager.example.invalid'
    ENV['JWT_SECRET_KEY'] = 'synthetic-oracle-key'
    Time.use_zone('Europe/Berlin') { Users::CreationWebhookJob.new.perform(user.id) }
  ensure
    %w[MANAGER_URL JWT_SECRET_KEY].each { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
    user.delete
  end
  puts JSON.generate(trials: observations, skip: skip, manager: payload)
end
