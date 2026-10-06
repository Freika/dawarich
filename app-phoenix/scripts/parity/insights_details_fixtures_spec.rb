# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'
require 'bigdecimal'

RSpec.describe 'Phoenix fixtures: the insights details frame and the cache entries Rails writes', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/insights') }
  let(:cache_dir) { Rails.root.join('app-phoenix/test/fixtures/rails_cache') }
  let(:settings) do
    { 'timezone' => 'Europe/Berlin', 'maps' => { 'distance_unit' => 'km' }, 'onboarding_completed' => true }
  end
  let(:zone) { ActiveSupport::TimeZone['Europe/Berlin'] }
  let(:leipzig) { [51.3397, 12.3731] }

  around do |example|
    caching = InsightsController.perform_caching
    InsightsController.perform_caching = true
    travel_to(Time.utc(2026, 6, 15, 10)) { example.run }
  ensure
    InsightsController.perform_caching = caching
  end

  def raw(key, store = Rails.cache)
    store.redis.then { |client| client.respond_to?(:with) ? client.with { _1.get(key) } : client.get(key) }
  end

  def cache_redis(&block)
    Rails.cache.redis.then { |client| client.respond_to?(:with) ? client.with(&block) : block.call(client) }
  end

  def details_isolated
    connection = ActiveRecord::Base.connection
    sequences = %w[users points visits tracks track_segments stats digests countries
                   notifications].index_with do |table|
      connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")
    end
    caching = InsightsController.perform_caching
    locale = I18n.locale
    cache = {}
    RSpec::Mocks.with_temporary_scope do
      %i[write_entry delete_entry].each do |method|
        allow(Rails.cache).to receive(method).and_wrap_original do |original, key, *args, **kwargs|
          remember_cache(cache, key)
          original.call(key, *args, **kwargs)
        end
      end
      allow(Rails.cache).to receive(:delete_matched).and_wrap_original do |original, pattern, **kwargs|
        cache_redis { |redis| redis.scan_each(match: pattern).each { |key| remember_cache(cache, key) } }
        original.call(pattern, **kwargs)
      end
      ActiveRecord::Base.transaction(requires_new: true) do
        sequences.each_key { |table| connection.execute("SELECT setval('#{table}_id_seq', 960500, false)") }
        cache_redis do |redis|
          ['insights/yearly_digest/960[12]/*', 'views/insights/details:*/960[12]/*'].each do |pattern|
            redis.scan_each(match: pattern).each do |key|
              remember_cache(cache, key)
              redis.del(key)
            end
          end
        end
        yield
        raise ActiveRecord::Rollback
      end
    ensure
      restore_cache(cache)
    end
  ensure
    sequences&.each do |table, state|
      connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                         "#{connection.quote(state.fetch('is_called'))})")
      expect(connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")).to eq(state), table
    end
    InsightsController.perform_caching = caching
    I18n.locale = locale if locale
  end

  def remember_cache(cache, key)
    return if cache.key?(key)

    cache_redis do |redis|
      ttl = redis.pttl(key)
      cache[key] =
        [redis.get(key), ttl.negative? ? ttl : Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl / 1000.0]
    end
  end

  def restore_cache(cache)
    cache_redis do |redis|
      cache.each do |key, (bytes, expiry)|
        clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        remaining = expiry.negative? ? expiry : ((expiry - clock) * 1000).floor
        if bytes.nil? || remaining == -2 || remaining.zero? || (expiry.positive? && remaining.negative?)
          redis.del(key)
        elsif remaining == -1
          redis.set(key, bytes)
        else
          redis.set(key, bytes, px: remaining)
        end
      end
    end
  end

  def user!(id, email)
    user = create(:user, id:, email:, settings:, plan: :pro)
    user.update_columns(encrypted_password: '', api_key: "insights-fixture-#{id}")
    user.reload
  end

  def point!(user, lat, time, city:)
    user.points.create!(lonlat: "POINT(#{leipzig[1]} #{lat})", timestamp: time.to_i, city:,
                        country_name: city && 'Germany', reverse_geocoded_at: time, created_at: time,
                        tracker_id: 'insights-fixture', anomaly: false)
  end

  def walk!(user, start, steps, city:, south: 0.0)
    time = zone.parse(start)
    (0..steps).each { |step| point!(user, leipzig[0] - south + (step * 0.002), time + (step * 600), city:) }
  end

  def calculate!(user, months)
    months.each { |year, month| Stats::CalculateMonth.new(user.id, year, month).call }
    digests!(user, months)
    user.digests.order(:period_type, :year, :month).each_with_index do |digest, index|
      id = (user.id * 10) + index
      digest.update_columns(id:, sharing_uuid: format('00000000-0000-4000-8000-%012d', id))
    end
  end

  def digests!(user, months)
    months.each { |year, month| Users::Digests::CalculateMonth.new(user.id, year, month).call }
    months.map(&:first).uniq.each { |year| Users::Digests::CalculateYear.new(user.id, year).call }
  end

  def visit!(user, name, start, minutes)
    started_at = zone.parse(start)
    user.visits.create!(name:, started_at:, ended_at: started_at + minutes.minutes, duration: minutes,
                        status: :confirmed)
  end

  def frame(path)
    keys = []
    subscriber = ->(*, payload) { keys << payload[:key].to_s }
    ActiveSupport::Notifications.subscribed(subscriber, 'cache_write.active_support') do
      get path, headers: { 'Turbo-Frame' => 'insights_details' }
    end
    expect(response).to have_http_status(:ok)
    body = response.body
    close = body.rindex('</turbo-frame>') + '</turbo-frame>'.length
    [body[body.index('<turbo-frame id="insights_details">')...close], keys]
  end

  def yearly_cache(user, year)
    updated = user.digests.yearly.find_by!(year:).updated_at.to_i
    key = "insights/yearly_digest/#{user.id}/#{year}/#{updated}"
    { 'key' => key, 'wire' => Base64.strict_encode64(raw(key)) }
  end

  def rows(users)
    {
      'users' => users.map do |user|
        { 'id' => user.id, 'email' => user.email, 'settings' => user.settings, 'plan' => user.plan_before_type_cast }
      end,
      'stats' => Stat.where(user: users).order(:user_id, :year, :month).map do |stat|
        stat.attributes.slice('user_id', 'year', 'month', 'distance', 'toponyms', 'daily_distance',
                              'created_at', 'updated_at')
      end,
      'digests' => Users::Digest.where(user: users).order(:id).map do |digest|
        digest.attributes.except('sent_at').merge('period_type' => digest.period_type_before_type_cast)
      end,
      'visits' => Visit.where(user: users).order(:user_id, :started_at).map do |visit|
        visit.attributes.slice('user_id', 'name', 'started_at', 'ended_at', 'duration').merge('status' => 1)
      end
    }
  end

  def reader!
    reader = user!(9601, 'insights-reader@dawarich.test')
    walk!(reader, '2023-07-14 09:00', 20, city: 'Leipzig')
    walk!(reader, '2024-03-05 09:00', 10, city: 'Leipzig')
    walk!(reader, '2024-03-06 09:00', 6, city: 'Leipzig')
    walk!(reader, '2024-03-07 09:00', 14, city: 'Leipzig')
    walk!(reader, '2024-03-20 09:00', 8, city: 'Markkleeberg', south: 0.04)
    walk!(reader, '2024-04-10 14:00', 12, city: 'Leipzig')
    point!(reader, leipzig[0], zone.parse('2024-04-20 12:00'), city: nil)
    visit!(reader, 'Office', '2024-03-05 12:00', 120)
    visit!(reader, 'Office', '2024-03-06 12:00', 120)
    visit!(reader, 'Home', '2024-04-10 18:00', 90)
    calculate!(reader, [[2023, 7], [2024, 3], [2024, 4]])
    reader
  end

  def active!
    active = user!(9602, 'insights-activity@dawarich.test')
    walk!(active, '2024-03-05 09:00', 6, city: 'Leipzig')
    track = create(:track, user: active, start_at: zone.parse('2024-03-05 10:00'),
                           end_at: zone.parse('2024-03-05 10:10'),
                           original_path: 'LINESTRING(12.3731 51.3397, 12.3731 51.3417)')
    create(:track_segment, :walking, track:, duration: 600)
    visit!(active, '<img src=x onerror="alert(1)"> fixture', '2024-03-05 12:00', 60)
    calculate!(active, [[2024, 3]])
    active
  end

  it 'selected details generator restores every advanced sequence and touched cache TTL on an escaping error' do
    connection = ActiveRecord::Base.connection
    tables = %w[users points visits tracks track_segments stats digests countries notifications]
    sequences = tables.index_with { |table| connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq") }
    key = 'insights/yearly_digest/9601/2024/1710000000'
    sentinel = 'a12d1b4/unrelated'
    cache = {}
    [key, sentinel, 'a12d1b4/new-key'].each { |name| remember_cache(cache, name) }
    Rails.cache.write(key, 'prior snapshot', expires_in: 5.minutes)
    Rails.cache.write(sentinel, 'untouched', expires_in: 10.minutes)
    prior = raw(key)
    ttl = cache_redis { |redis| redis.pttl(key) }
    caching = InsightsController.perform_caching

    expect do
      details_isolated do
        reader = reader!
        active!
        sign_in reader
        frame('/insights/details?year=2024&month=4')
        Rails.cache.write(key, 'replaced', expires_in: 1.hour)
        Rails.cache.write('a12d1b4/new-key', 'new', expires_in: 1.hour)
        InsightsController.perform_caching = false
        raise 'selected capture failure'
      end
    end.to raise_error('selected capture failure')

    sequences.each do |table, state|
      expect(connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")).to eq(state), table
    end
    expect(raw(key)).to eq(prior)
    expect(cache_redis { |redis| redis.pttl(key) }).to be_between(ttl - 30_000, ttl)
    expect(raw('a12d1b4/new-key')).to be_nil
    expect(Rails.cache.read(sentinel)).to eq('untouched')
    expect(InsightsController.perform_caching).to eq(caching)
  ensure
    restore_cache(cache) if cache
    sequences&.each do |table, state|
      connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                         "#{connection.quote(state.fetch('is_called'))})")
    end
  end

  it 'writes the details frames Rails renders for a Leipzig corpus and the yearly digest cache entries' do
    details_isolated { capture_details }
  end

  def capture_details
    reader = reader!
    active = active!
    User.where(id: [reader.id, active.id]).update_all(visits_redetected_at: Time.current)
    requests = [[reader, '/insights/details?year=2024&month=4', 'details-en.html'],
                [reader, '/insights/details?year=2024&month=4&locale=de', 'details-de.html'],
                [active, '/insights/details?year=2024', 'details-activity.html']] +
               %w[es fr pl ca zh].map do |locale|
                 [reader, "/insights/details?year=2024&month=4&locale=#{locale}", "details-#{locale}.html"]
               end
    captures = []
    written = requests.map do |user, path, fixture|
      reset!
      sign_in User.find(user.id)
      before = rows([user])
      markup, keys = frame(path)
      captures << { path:, body: markup, status: response.status, media_type: response.media_type,
                    location: response.location, vary: response.headers['Vary'],
                    cookie: response.headers['Set-Cookie'].present?, flash: flash.to_hash,
                    before:, after: rows([user]) }
      FixtureRecording.verify(dir.join(fixture), "#{markup}\n")
      keys.grep(%r{\Aviews/insights/details:})
    end

    templates = written.flatten.map { _1[%r{\Aviews/(insights/details:\h+)/}, 1] }.uniq
    digest = ActionView::Digestor.digest(name: 'insights/details', format: :html,
                                         finder: ApplicationController.new.lookup_context)
    expect(templates).to eq(["insights/details:#{digest}"])
    expect(active.digests.yearly.first.travel_patterns['activity_breakdown'].keys).to eq(['walking'])

    corpus = rows([reader, active]).merge(
      'template_digest' => templates.first,
      'cache' => [yearly_cache(reader, 2024), yearly_cache(active, 2024)],
      'requests' => requests.zip(written).map do |(user, path, fixture), keys|
        { 'user_id' => user.id, 'path' => path, 'fixture' => fixture, 'fragment_keys' => keys }
      end
    )
    FixtureRecording.verify(dir.join('details-corpus.json'), "#{JSON.pretty_generate(corpus.as_json)}\n")
    %w[04 05].each do |id|
      FixtureRecording.source_verify(dir.join("../stats/a12f3a-q#{id}.json"),
                                     "#{JSON.pretty_generate(captures.as_json)}\n")
    end
    index_rows = []
    [true, false].each do |self_hosted|
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      ['', '?year=2024', '?year=all', '?year=2024&month=4', '?year[]=2024', '?month[]=4',
       '?year=bad&month=99'].each do |query|
        reset!
        sign_in reader
        error = nil
        begin
          get("/insights#{query}")
        rescue StandardError => e
          error = { class: e.class.name, message: FixtureRecording.normalize(e.message) }
        end
        doc = Nokogiri::HTML5(error ? '' : response.body)
        doc.css('input[name="authenticity_token"]').each { _1['value'] = 'CSRF' }
        doc.css('meta[name="csrf-token"]').each { _1['content'] = 'CSRF' }
        doc.css('[nonce]').each { _1['nonce'] = 'NONCE' }
        index_rows << { path: "/insights#{query}", self_hosted:, error:,
                        status: error ? nil : response.status,
                          body: error ? nil : FixtureRecording.normalize(doc.to_html),
                        media_type: error ? nil : response.media_type,
                        location: error ? nil : response.location, flash: error ? nil : flash.to_hash }
      end
    end
    FixtureRecording.source_verify(dir.join('../stats/a12f3a-q03.json'),
                                   "#{JSON.pretty_generate(index_rows.as_json)}\n")
  end

  it 'writes the activity card Rails renders for fresh and persisted JSON key order' do
    fresh = { 'walking' => { 'duration' => 600, 'percentage' => 14 },
              'stationary' => { 'duration' => 1800, 'percentage' => 43 },
              'flying' => { 'duration' => 1800, 'percentage' => 43 } }
    digest = Users::Digest.create!(user: create(:user), year: 2024, period_type: :yearly,
                                   travel_patterns: { 'activity_breakdown' => fresh })
    persisted = Users::Digest.find(digest.id).travel_patterns['activity_breakdown']
    expect(persisted.keys).to eq(%w[flying walking stationary])

    { 'fresh' => fresh, 'persisted' => persisted }.each do |state, value|
      markup = ApplicationController.render(partial: 'insights/activity_breakdown',
                                            assigns: { activity_breakdown: value })
      FixtureRecording.verify(dir.join("activity-#{state}.html"), markup)
    end
  end

  it 'writes the cache entries Rails writes for each value type the details reader meets' do
    digest = Users::Digest.new(id: 71, user_id: 93, year: 2024, period_type: :yearly, distance: 38_000,
                               updated_at: Time.utc(2024, 3, 5),
                               travel_patterns: { 'weekly_pattern' => [1, 2, 3, 4, 5, 6, 7] })
    digest.user = User.new(id: 93, email: 'cache-fixture@dawarich.test', settings:)
    values = {
      'nil' => nil, 'false' => false, 'true' => true, 'integer' => 81, 'negative' => -901, 'bignum' => 2**90,
      'float' => 1.25, 'hash' => { 'plan' => 'pro', :enabled => true, 'limits' => [120, nil, false] },
      'utf8' => 'Leipzig — Lindenau', 'ascii' => 'ascii'.encode(Encoding::US_ASCII), 'binary' => "\x00\xff".b,
      'safe_html' => '<p>synthetic &amp; escaped</p>'.html_safe,
      'compressed_html' => ('<p>synthetic fragment</p>' * 120).html_safe,
      'compressed_string' => '<p>Leipzig fragment</p>' * 120,
      'time' => Time.utc(2024, 3, 5, 12, 34, 56, 123_456), 'date' => Date.new(2024, 3, 5),
      'decimal' => BigDecimal('1234.5678'), 'digest' => digest
    }
    values.each do |name, value|
      Rails.cache.write("codec/#{name}", value, expires_in: 2.minutes)
      expect(Rails.cache.read("codec/#{name}")).to eq(value) unless name == 'digest'
      File.binwrite(cache_dir.join("codec-#{name}.wire"), raw("codec/#{name}"))
    end

    original = ActiveSupport::Cache.format_version
    [7.0, 7.1].each do |version|
      ActiveSupport::Cache.format_version = version
      store = ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch('REDIS_URL'))
      store.write("codec/legacy-#{version}", values['hash'], expires_in: 2.minutes)
      wire = raw("codec/legacy-#{version}", store)
      File.binwrite(cache_dir.join("codec-marshal_#{version.to_s.tr('.', '_')}.wire"), wire)
    ensure
      ActiveSupport::Cache.format_version = original
    end
  end
end
