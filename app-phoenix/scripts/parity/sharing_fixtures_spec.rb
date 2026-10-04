# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the public shared-link pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/sharing') }
  let(:now) { Time.utc(2026, 10, 2, 12, 0, 0) }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }
  let(:phrase) { 'blau-tiger-berg' }
  let(:header_names) do
    %w[content-type x-robots-tag cache-control location x-frame-options x-xss-protection x-content-type-options
       x-permitted-cross-domain-policies referrer-policy retry-after]
  end

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def link_id(number) = format('a9500000-0000-4000-8000-%012d', number)

  def links
    [
      [1, 'live', nil, 'Leipzig live', nil, { 'show_photos' => false, 'show_route' => true }],
      [2, 'live', nil, 'Leipzig <b>&</b> "Saale"', phrase, { 'show_route' => false }, 7.days.to_i],
      [3, 'timeline', nil, 'Auensee', nil, { 'start_date' => '2026-05-09', 'end_date' => '2026-05-12' }],
      [4, 'timeline', nil, 'One day', nil, { 'start_date' => '2026-05-10', 'end_date' => '2026-05-10' }],
      [5, 'timeline', nil, 'Spring', nil, { 'start_date' => '2026-04-28', 'end_date' => '2026-05-03' }],
      [6, 'timeline', nil, 'New year', nil, { 'start_date' => '2025-12-30', 'end_date' => '2026-01-02' }],
      [7, 'trip', 990_001, 'Gone trip', nil, {}],
      [8, 'track', 990_002, 'Gone track', nil, {}],
      [9, 'live', nil, 'Revoked', nil, {}, nil, true],
      [10, 'live', nil, 'Expired', nil, {}, -1.day.to_i],
      [11, 'live', nil, 'Route yes', nil, { 'show_route' => 'yes' }],
      [12, 'live', nil, 'Route zero', nil, { 'show_route' => '0' }],
      [13, 'live', nil, 'Route unset', nil, {}],
      [14, 'timeline', nil, 'Blank phrase', " \t", { 'start_date' => '2026-05-09', 'end_date' => '2026-05-09' }]
    ]
  end

  def rows
    links.map do |number, type, resource_id, name, magic_phrase, settings, expires_offset, revoked|
      { id: link_id(number), user_id: 9901, resource_type: SharedLink.resource_types.fetch(type), resource_id:,
        name:, magic_phrase:, settings:, expires_at: expires_offset && (now + expires_offset).iso8601(6),
        revoked_at: revoked ? (now - 1.day).iso8601(6) : nil, created_at: now.iso8601(6) }
    end
  end

  def insert!
    user = create(:user, id: 9901, email: 'a9s-9901@dawarich.test', changelog_consent: :declined)
    user.update_columns(settings: user.settings.merge('timezone' => 'Europe/Berlin', 'onboarding_completed' => true),
                        api_key: 'a9s-k-9901')
    SharedLink.insert_all(rows.map { |row| row.merge(updated_at: row[:created_at]) })
    { id: 9901, email: user.email, settings: user.reload.settings, api_key: user.api_key }
  end

  def write_json(name, data)
    encoded = "#{Oj.dump(data.deep_stringify_keys, mode: :strict, indent: 2)}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(dir.join(name), encoded)
    else
      expect(JSON.parse(dir.join(name).read)).to eq(JSON.parse(encoded))
    end
  end

  def set_cookies
    Array(response.headers['Set-Cookie']).flat_map { |line| line.split("\n") }.to_h do |line|
      name, *attributes = line.split(';').map(&:strip)
      [name.split('=', 2).first, attributes.map { |a| a.downcase.sub(/\Aexpires=.*/, 'expires') }.sort]
    end
  end

  def scrub(node)
    node.css('meta[name="csrf-token"]').each { |meta| meta['content'] = 'CSRF' }
    node.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
    node
  end

  def store(name, doc)
    head = scrub(doc.at_css('head'))
    scripts = { 'importmap' => head.css('script[type="importmap"]').size,
                'modulepreload' => head.css('link[rel="modulepreload"]').size,
                'translations' => head.css('script#i18n-translations').size }
    head.css('script[type="importmap"], link[rel="modulepreload"], script#i18n-translations').each(&:remove)
    html = { "pages/#{name}.head.html" => head.inner_html.gsub(/[ \t]+\n/, "\n").squeeze("\n"),
             "pages/#{name}.html" => scrub(doc.at_css('body')).inner_html.gsub(/[ \t]+\n/, "\n") }
    html.each do |path, body|
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        File.write(dir.join(path), body)
      else
        expect(dir.join(path).read).to eq(body)
      end
    end
    { title: doc.at_css('title').text, html_lang: doc.at_css('html')['lang'], scripts: }
  end

  def capture(name, verb, path, params: nil, cookie: nil, keep: true)
    reset!
    id = path[%r{/s/([^/?]+)}, 1]
    before = SharedLink.find_by(id:)&.view_count
    send(verb, path, params:, headers: cookie ? { 'Cookie' => cookie } : {})
    entry = { name:, verb:, path:, params:, cookie: cookie&.split('=')&.first, status: response.status,
              headers: header_names.index_with { |header| response.headers[header] }.compact,
              etag: response.headers['ETag'].present?, set_cookies:,
              touched: before && (SharedLink.find(id).view_count - before) }
    html = keep && response.media_type == 'text/html' && response.body != ''
    entry.merge!(store(name, Nokogiri::HTML5(response.body))) if html
    entry
  end

  def unlock_cookie(id)
    line = Array(response.headers['Set-Cookie']).flat_map { |l| l.split("\n") }
                                                .find { |l| l.start_with?("shared_link_#{id}=") }
    line.split(';').first
  end

  def pages
    show = { 'live_en' => 1, 'live_named_prompt_en' => 2, 'timeline_range_en' => 3, 'timeline_day_en' => 4,
             'timeline_year_en' => 5, 'timeline_years_en' => 6, 'missing_trip_en' => 7, 'missing_track_en' => 8,
             'not_found_revoked_en' => 9, 'not_found_expired_en' => 10, 'live_route_yes_en' => 11,
             'live_route_zero_en' => 12, 'live_route_unset_en' => 13, 'timeline_blank_phrase_en' => 14,
             'not_found_unknown_en' => 99 }
    entries = show.map { |name, number| capture(name, :get, "/s/#{link_id(number)}") }
    entries += { 'live_de' => 1, 'live_named_prompt_de' => 2, 'timeline_range_de' => 3, 'timeline_years_de' => 6,
                 'missing_track_de' => 8, 'not_found_revoked_de' => 9 }.map do |name, number|
      capture(name, :get, "/s/#{link_id(number)}?locale=de")
    end
    entries + unlocks
  end

  def unlocks
    entries = [capture('unlock_wrong_en', :post, "/s/#{link_id(2)}/unlock", params: { phrase: 'falsch' }),
               capture('unlock_wrong_de', :post, "/s/#{link_id(2)}/unlock?locale=de", params: { phrase: 'falsch' }),
               capture('unlock_unknown_en', :post, "/s/#{link_id(99)}/unlock", params: { phrase: phrase }),
               capture('unlock_open_en', :post, "/s/#{link_id(1)}/unlock"),
               capture('unlock_right_en', :post, "/s/#{link_id(2)}/unlock", params: { phrase: phrase })]
    cookie = unlock_cookie(link_id(2))
    entries << capture('unlocked_live_named_en', :get, "/s/#{link_id(2)}", cookie:)
    entries << capture('unlock_blank_en', :post, "/s/#{link_id(14)}/unlock", params: { phrase: " \t" })
    entries << capture('unlocked_blank_en', :get, "/s/#{link_id(14)}", cookie: unlock_cookie(link_id(14)))
  end

  def raw_post(path, body)
    env = Rack::MockRequest.env_for(path, method: 'POST', input: body, 'REMOTE_ADDR' => '127.0.0.1',
                                          'CONTENT_TYPE' => 'application/x-www-form-urlencoded')
    status, headers, = Rails.application.call(env)
    volatile = %w[x-request-id x-runtime]
    { status:, headers: headers.to_a.map { |k, v| [k, volatile.include?(k) ? 'VOLATILE' : v] } }
  end

  def unmask(value)
    decoded = Base64.urlsafe_decode64(value)
    decoded[0, 32].bytes.zip(decoded[32, 32].bytes).map { |pad, byte| pad ^ byte }.pack('C*').unpack1('H*')
  end

  def form_csrf
    fixed = Base64.urlsafe_encode64('phoenix-a9s-csrf-fixture-value-0', padding: false)
    allow_any_instance_of(Shared::LinksController).to receive(:generate_csrf_token).and_return(fixed)
    reset!
    get "/s/#{link_id(2)}"
    doc = Nokogiri::HTML5(response.body)
    { session: session[:_csrf_token], action: "/s/#{link_id(2)}/unlock",
      form: unmask(doc.at_css('input[name="authenticity_token"]')['value']),
      meta: unmask(doc.at_css('meta[name="csrf-token"]')['content']) }
  end

  before { FileUtils.mkdir_p(dir.join('pages')) }

  it 'writes the public shared-link pages and the seed they render' do
    expect(Rails.application.secret_key_base).to eq(secret)
    expect(ENV.values_at('TIME_ZONE', 'SELF_HOSTED')).to eq([nil, nil])

    travel_to now do
      user = insert!
      write_json('pages.json', { now: now.iso8601, pages: })
      write_json('seed.json', { users: [user], shared_links: rows })
      write_json('csrf.json', form_csrf)
    end
  end

  def counters
    ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT key, value, ceil(extract(epoch FROM expires_at - statement_timestamp()))::int
      FROM phoenix.counters ORDER BY key
    SQL
  end

  it 'writes the unlock throttle as rack-attack keeps it' do
    store = Rack::Attack.cache.store
    phoenix_counters!
    Rack::Attack.cache.store = RackAttack::PhoenixCounterStore.new
    Rack::Attack.enabled = true
    travel_to now do
      insert!
      first = 6.times.map do
        capture('throttle', :post, "/s/#{link_id(2)}/unlock", params: { phrase: 'falsch' }, keep: false)
          .merge(body: response.body)
      end
      throttled = first.last.except(:name, :touched)
      keys = counters
      raise "unexpected TTL #{keys.inspect}" unless keys.all? { |_k, _v, ttl| ttl.between?(290, 301) }

      raw = raw_post("/s/#{link_id(2)}/unlock", 'phrase=falsch')
      seeded = "rack::attack:#{now.to_i / 300}:shared_links/unlock:198.51.100.4:#{link_id(2)}"
      ActiveRecord::Base.connection.execute('DELETE FROM phoenix.counters')
      Rack::Attack.cache.store.increment(seeded, 5, expires_in: 301)
      reset!
      post "/s/#{link_id(2)}/unlock", params: { phrase: }, env: { 'REMOTE_ADDR' => '198.51.100.4' }
      write_json('throttle.json', { now: now.iso8601, statuses: first.map { |e| e[:status] }, throttled:, raw:,
                                    keys: keys.map { |k, v, _ttl| { key: k, count: v, expires_in: 301 } },
                                    seeded: { key: seeded, count: 5, status: response.status },
                                    redis_db: ENV.fetch('RACK_ATTACK_REDIS_DB', '3').to_i })
    end
  ensure
    Rack::Attack.cache.store = store
    Rack::Attack.enabled = false
  end
end
