# frozen_string_literal: true

require 'ostruct'
require 'timeout'
require_relative 'oracle_support'

RecoveryOracle.deterministic!('race-raw-')
User.class_eval { def send_devise_notification(*); end }
module RaceBarrier
  READY = Queue.new
  RELEASE = Queue.new

  class << self
    attr_accessor :active
  end
end
User.singleton_class.prepend(Module.new do
  def find_or_initialize_with_error_by(attribute, value, *)
    result = super
    if RaceBarrier.active && %i[reset_password_token unlock_token].include?(attribute)
      RaceBarrier::READY << true
      RaceBarrier::RELEASE.pop
    end
    result
  end
end)

FIELDS = %w[reset_password_token reset_password_sent_at unlock_token locked_at failed_attempts failed_otp_attempts
            otp_locked_at sign_in_count current_sign_in_at last_sign_in_at].freeze
SETUP = { locked_at: RecoveryOracle::NOW, failed_attempts: 11, failed_otp_attempts: 10,
          otp_locked_at: RecoveryOracle::NOW, sign_in_count: 0 }.freeze

def race_actor(kind, raw, index)
  Thread.new do
    Rails.application.executor.wrap do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        pid = connection.select_value('SELECT pg_backend_pid()')
        password = "source-race-#{index}-password12"
        resource = if kind == 'reset'
                     User.reset_password_by_token(reset_password_token: raw, password:,
                                                  password_confirmation: password)
                   else
                     User.unlock_access_by_token(raw)
                   end
        if kind == 'reset' && resource.errors.empty?
          resource.unlock_access!
          resource.update_tracked_fields!(OpenStruct.new(remote_ip: "127.0.0.#{index + 1}"))
        end
        { pid:, success: resource.errors.empty?, errors: resource.errors.details }
      end
    end
  end
end

result = {}
%w[reset unlock].each do |kind|
  user = RecoveryOracle.fresh_user("recovery-race-#{kind}-oracle@dawarich.test")
  user.update_columns(SETUP)
  raw = kind == 'reset' ? user.send_reset_password_instructions : user.send_unlock_instructions
  before = RecoveryOracle.state(user, FIELDS)
  ActiveRecord::Base.connection_pool.release_connection
  RaceBarrier.active = true
  actors = 2.times.map { |index| race_actor(kind, raw, index) }
  Timeout.timeout(10) { 2.times { RaceBarrier::READY.pop } }
  2.times { RaceBarrier::RELEASE << true }
  calls = Timeout.timeout(10) { actors.map(&:value) }
  RaceBarrier.active = false
  final = RecoveryOracle.state(user, FIELDS + %w[current_sign_in_ip last_sign_in_ip])
  winners = 2.times.select { |index| user.valid_password?("source-race-#{index}-password12") }
  ips = final.extract!('current_sign_in_ip', 'last_sign_in_ip').values.uniq
  actor_ips = kind == 'reset' ? [['127.0.0.1'], ['127.0.0.2']] : [[nil]]
  result[kind] = {
    raw:, before:, distinct_backends: calls.map { _1[:pid] }.uniq.size == 2,
    calls: calls.map { _1.except(:pid) }, final:,
    password_winners: kind == 'reset' ? winners.size : nil,
    sign_in_ips_from_one_actor: actor_ips.include?(ips)
  }
end

RecoveryOracle.write(ARGV.fetch(0), result)
puts 'Captured two-backend Rails recovery races behind a post-lookup barrier; no mail'
