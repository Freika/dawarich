# frozen_string_literal: true

module RateLimitFixtureSupport
  SECRET = JSON.parse(Rails.root.join('app-phoenix/test/fixtures/rails_cookies.json').read).fetch('rails_test_secret')
  NOW = Time.utc(2026, 10, 2, 12, 0, 17)
  PATH = Rails.root.join('app-phoenix/test/fixtures/rate_limit/corpus.json')
  HOST = 'www.example.com'
  KEYS = {
    'lite' => 'a13cliteqqqqqqqqqqqqqqqq', 'pro' => 'a13cproqqqqqqqqqqqqqqqqq',
    'family' => 'a13cfamilyqqqqqqqqqqqqqq', 'member' => 'a13cmemberqqqqqqqqqqqqqq',
    'lapsed' => 'a13clapsedqqqqqqqqqqqqqq', 'deleted' => 'a13cdeletedqqqqqqqqqqqqq',
    'mixed' => 'A13cMixedQqqqqqqqqqqqqqq', 'unknown' => 'a13cunknownqqqqqqqqqqqqq'
  }.freeze
  WEBHOOK = 'a13cwebhookqqqqqqqqqqqqq'
  CHALLENGE = 'a13cchallengeqqqqqqqqqqq'
  SESSIONS = {
    'otp' => { 'otp_user_id' => 7 }, 'otp_blank' => { 'otp_user_id' => '' },
    'otp_false' => { 'otp_user_id' => false }, 'link' => { 'pending_oauth_link' => { 'user_id' => 9 } },
    'link_string' => { 'pending_oauth_link' => 'x' }, 'link_empty' => { 'pending_oauth_link' => {} }
  }.freeze
  NAMES = %w[content-type cache-control retry-after vary].freeze

  class RecordingStore
    attr_reader :calls

    def initialize
      @data = {}
      @calls = []
    end

    def increment(key, amount = 1, expires_in:, **)
      @calls << [key, expires_in.to_i]
      @data[key] = @data.fetch(key, 0) + amount
    end

    def write(key, value, **) = (@data[key] = value)
    def seed(key, value) = (@data[key] = value)
  end

  module_function

  def write? = ENV['WRITE_PHOENIX_FIXTURES'] == '1'
  def stored = PATH.exist? ? JSON.parse(PATH.read) : {}
  def normalized(data) = JSON.parse(Oj.dump(data, mode: :strict))

  def write(data)
    FileUtils.mkdir_p(PATH.dirname)
    PATH.write("#{Oj.dump(data, mode: :strict, indent: 2)}\n")
  end

  def throttle_table
    request = Rack::Attack::Request.new(Rack::MockRequest.env_for('/'))
    Rack::Attack.throttles.map do |name, throttle|
      limit = throttle.limit.respond_to?(:call) ? throttle.limit.call(request) : throttle.limit
      { 'name' => name, 'limit' => limit, 'period' => throttle.period }
    end
  end

  def session_cookie(name, stored_cookies)
    stored_cookies[name] || begin
      jar = ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_HOST' => HOST)).cookie_jar
      jar.encrypted['_dawarich_session'] = SESSIONS.fetch(name).merge('session_id' => "a13c#{name}")
      Rack::Utils.escape(jar['_dawarich_session'])
    end
  end
end
