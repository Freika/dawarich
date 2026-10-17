# frozen_string_literal: true

require 'devise'
require 'devise/models/trackable'
require 'json'
require 'time'

class SyntheticTrackableUser
  include Devise::Models::Trackable

  attr_accessor :sign_in_count, :current_sign_in_at, :last_sign_in_at,
                :current_sign_in_ip, :last_sign_in_ip
end

now = Time.iso8601('2026-10-01T12:00:00.123456Z')
old = Time.iso8601('2026-09-30T12:00:00.654321Z')
cases = [
  ['first', 0, nil, nil],
  ['later', 4, old, '192.0.2.20'],
  ['partial', nil, old, nil]
]
fields = %i[sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip]
original_clock = Time.method(:now)
Time.define_singleton_method(:now) { now }

begin
  results = cases.map do |name, count, at, ip|
    user = SyntheticTrackableUser.new
    user.sign_in_count = count
    user.current_sign_in_at = at
    user.current_sign_in_ip = ip
    before = fields.index_with { |field| user.public_send(field) }
    user.update_tracked_fields(Struct.new(:remote_ip).new('192.0.2.10'))
    after = fields.index_with { |field| user.public_send(field) }

    encode = lambda do |attributes|
      attributes.transform_values { |value| value.is_a?(Time) ? value.utc.iso8601(6) : value }
    end

    { name: name, before: encode.call(before), after: encode.call(after) }
  end

  puts JSON.pretty_generate(
    devise_version: Gem.loaded_specs.fetch('devise').version.to_s,
    ruby_version: RUBY_VERSION,
    now: now.iso8601(6),
    remote_ip: '192.0.2.10',
    cases: results
  )
ensure
  Time.define_singleton_method(:now, original_clock)
end
