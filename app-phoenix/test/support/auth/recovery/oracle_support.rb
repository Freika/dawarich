# frozen_string_literal: true

require 'digest'
require 'json'
require 'active_support/testing/time_helpers'

module RecoveryOracle
  SECRET = 'phoenix-a2-cookie-fixture-secret-not-for-production'
  NOW = Time.utc(2026, 10, 1, 12)
  TOKEN_COLUMNS = %w[reset_password_token unlock_token].freeze

  extend ActiveSupport::Testing::TimeHelpers

  module_function

  def guard!
    database = ActiveRecord::Base.connection_db_config.database
    return if Rails.env.test? && database.start_with?('dawarich_test_a11') && Devise.secret_key == SECRET

    raise 'A11 recovery oracle requires its own test database and the synthetic secret'
  end

  def quiet_delivery!
    ActiveJob::Base.queue_adapter = :test
    ActionMailer::Base.delivery_method = :test
    ActionMailer::Base.perform_deliveries = false
  end

  def deterministic!(prefix)
    counters = Hash.new(0)
    travel_to(NOW)
    Devise.singleton_class.prepend(Module.new do
      define_method(:friendly_token) do |length = 20|
        counters[:token] += 1
        format('%<prefix>s%<n>04d', prefix:, n: counters[:token]).ljust(length, 'q')
      end
    end)
    BCrypt::Engine.singleton_class.prepend(Module.new do
      define_method(:generate_salt) do |cost = self.cost|
        counters[:salt] += 1
        seed = Digest::MD5.digest("#{prefix}#{counters[:salt]}")
        __bc_salt('$2a$', [cost.to_i, BCrypt::Engine::MIN_COST].max, seed)
      end
    end)
  end

  def fresh_user(email)
    User.unscoped.where(email:).delete_all
    user = User.new(email:, password: 'safepassword12', status: :active, active_until: Time.utc(2099))
    user.skip_auto_trial = true
    user.skip_family_sync = true
    user.save!
    user
  end

  def notifications
    @notifications ||= []
  end

  def halves(value)
    return value unless value.is_a?(String) && value.size == 64

    [value[0, 32], value[32, 32]]
  end

  def state(user, fields)
    user.reload.attributes.slice(*fields).to_h do |name, value|
      value = value.utc.iso8601(6) if value.respond_to?(:iso8601)
      [name, TOKEN_COLUMNS.include?(name) ? halves(value) : value]
    end
  end

  def write(path, data)
    File.write(path, "#{JSON.pretty_generate(data)}\n")
  end
end

RecoveryOracle.guard!
RecoveryOracle.quiet_delivery!
