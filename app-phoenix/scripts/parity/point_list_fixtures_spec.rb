# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: point lists and addresses', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_data') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:accept) { 'text/html, application/xhtml+xml' }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    FileUtils.mkdir_p(dir)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return('a6s3-synthetic-jwt-not-for-production')
  end

  def reader(id, zone: 'UTC', plan: :pro, unit: 'km')
    create(:user, id:, email: "a6s3-#{id}@example.invalid", theme: 'light', plan:,
                  changelog_consent: :declined, created_at: now, updated_at: now).tap do |user|
      user.update_columns(api_key: "a6s3-k-#{id}", visits_redetected_at: now - 10.days,
                          settings: user.settings.merge('onboarding_completed' => true, 'timezone' => zone,
                                                        'maps' => { 'distance_unit' => unit }))
      user.reload
    end
  end

  def point!(user, id, at, **attrs)
    Point.insert!({ id:, user_id: user.id, timestamp: at.to_i, lonlat: 'POINT(12.373468123456 51.339700123456)',
                    created_at: now, updated_at: now }.merge(attrs))
  end

  def import!(user, id, name, at)
    Import.insert!({ id:, user_id: user.id, name:, created_at: at, updated_at: at })
  end

  def user_row(user)
    user.attributes.slice('id', 'email', 'theme', 'settings', 'admin', 'api_key').merge(
      'status' => User.statuses[user.status], 'plan' => User.plans[user.plan],
      'subscription_source' => User.subscription_sources[user.subscription_source],
      'changelog_consent' => User.changelog_consents[user.changelog_consent],
      'active_until' => user.active_until&.utc&.iso8601(6),
      'visits_redetected_at' => user.visits_redetected_at&.utc&.iso8601(6)
    )
  end

  def rows(user)
    %w[imports points].to_h do |table|
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE user_id = #{Integer(user.id)} ORDER BY t.id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def capture(name, user, path, at: now, frame: nil, status: 200, expected: {}, foreign: nil, geocoding: true)
    travel_to at do
      Rails.cache.clear
      reset!
      sign_in user if user
      headers = { 'Accept' => accept }
      headers['Turbo-Frame'] = frame if frame
      get(path, headers:)
      expect(response.status).to eq(status)
      expect(response.media_type).to eq('text/html')
      doc = Nokogiri::HTML5(response.body)
      doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
      doc.css('meta[name="csrf-token"]').each { |node| node['content'] = 'CSRF' }
      doc.css('[signed-stream-name]').each { |node| node['signed-stream-name'] = 'SIGNED' }
      body = if status != 200
               ''
             elsif frame || path.include?('/address')
               doc.to_html.gsub(%r{(/auth/dawarich\?token=)[^&"]+}, '\1REDACTED')
             else
               doc.at_css('body > div.container > div.w-full > div.flex').inner_html
             end
      expected.each do |selector, value|
        nodes = doc.css(selector)
        value.is_a?(Integer) ? expect(nodes.size).to(eq(value)) : expect(nodes.first&.text).to(include(value))
      end
      if status == 200 && (path.start_with?('/points?') || path == '/points')
        expect(doc.css('thead th').map(&:text).map(&:strip)).to include('Coordinates')
        expect(doc.at_css('#bulk_destroy_form')['action']).to start_with('/points/bulk_destroy')
        expect(doc.at_css('input[name="start_at"]')).to be_present
      end
      expect(response.headers['Location']).to include('/users/sign_in') if status == 302
      expect(response.body).not_to include('point_839901') if path == '/points'
      state = { 'kind' => frame ? 'point_address' : 'points', 'path' => path, 'accept' => accept,
                'turbo_frame' => frame, 'now' => at.iso8601, 'status' => response.status,
                'title' => doc.at_css('title')&.text,
                'content_type' => response.media_type, 'vary' => response.headers['Vary'],
                'location' => response.headers['Location'], 'self_hosted' => DawarichSettings.self_hosted?,
                'geocoding' => geocoding, 'env' => { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
                'session' => { 'user_return_to' => session[:user_return_to], 'alert' => flash[:alert] },
                'user' => user && user_row(user), 'rows' => user ? rows(user) : {},
                'foreign' => foreign && { 'user' => user_row(foreign), 'rows' => rows(foreign) } }
      expect(body).not_to match(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./)
      File.write(dir.join("#{name}.html"), body)
      File.write(dir.join("#{name}.target.html"), doc.at_css("turbo-frame##{frame}").to_html) if frame && status == 200
      File.write(dir.join("#{name}.json"), "#{Oj.dump(state, mode: :strict, float_precision: 0, indent: 2)}\n")
      sign_out user if user
    end
  end

  def generate!
    travel_to now
    begin
      configure_instance_geocoding
      owner = reader(8301)
      foreign = reader(8399)
      point!(foreign, 839_901, now - 1.day)
      import!(owner, 83_011, 'Synthetic <one>.json', now - 2.days)
      import!(owner, 83_012, 'Empty.json', now - 1.day)
      51.times do |i|
        point!(owner, 830_101 + i, now - 1.day + i.minutes, import_id: 83_011, velocity: i.zero? ? -1.5 : 0)
      end
      Point.where(id: 830_102).update_all(velocity: nil, city: 'Fallback', country_name: 'Germany')
      Point.where(id: 830_103).update_all(velocity: 1.234,
                                          geodata: { 'properties' => { 'street' => 'Straße <&>', 'city' => 'Leipzig',
                                                                       'country' => 'Germany' } })
      Point.where(id: 830_104).update_all(geodata: { 'address' => { 'road' => 'Flat Road', 'city' => 'Berlin',
                                                                  'country' => 'Germany' } })
      Point.where(id: 830_105).update_all(velocity: -0.5, geodata: {})
      capture('points_page1', owner, '/points', expected: { '#points tbody tr' => 50, '#point_830151' => 1 }, foreign:)
      capture('points_page2', owner, '/points?page=2', expected: { '#points tbody tr' => 1, '#point_830101' => 1 })
      capture('points_page_out', owner, '/points?page=3', expected: { '#points tbody tr' => 0 })
      capture('points_asc', owner, '/points?order_by=asc',
              expected: { '#point_830103' => '51.339700, 12.373468', '#point_830101' => '-1.5',
                          '#point_830104' => 'Flat Road, Berlin, Germany', '#point_830102' => 'Fallback, Germany',
                          '#point_830105' => '-0.5' })
      capture('points_desc', owner, '/points?order_by=desc', expected: { '#point_830151' => 1 })
      capture('points_epoch', owner, "/points?start_at=#{(now - 1.day).to_i}&end_at=#{(now - 1.day + 1.minute).to_i}",
              expected: { '#points tbody tr' => 2 })
      capture('points_iso', owner, '/points?start_at=2026-10-02T10:00:00Z&end_at=2026-10-02T10:01:00Z',
              expected: { '#points tbody tr' => 2 })
      capture('points_import', owner, '/points?import_id=83011&order_by=asc', expected: { '#points tbody tr' => 50 })
      capture('points_empty_import', owner, '/points?import_id=83012', expected: { '#points tbody tr' => 0 })
      capture('address_full', owner, '/points/830103/address', frame: 'point-address-830103',
expected: { '#point-address-830103' => 'Straße <&>, Leipzig, Germany' })
      capture('address_empty', owner, '/points/830102/address', frame: 'point-address-830102',
expected: { '#point-address-830102 > div' => 0 })
      capture('address_direct', owner, '/points/830103/address',
              expected: { 'html' => 1, '#point-address-830103' => 'Straße <&>' })
      capture('address_foreign', owner, '/points/839901/address', frame: 'point-address-839901', status: 404, foreign:)
      capture('address_guest', nil, '/points/830103/address', frame: 'point-address-830103', status: 302)
      capture('points_guest', nil, '/points', status: 302)
      empty = reader(8302)
      capture('points_empty', empty, '/points', expected: { '#points tbody tr' => 0 })
      march = reader(8303, zone: 'Europe/Berlin')
      point!(march, 830_301, Time.utc(2026, 2, 27, 23))
      capture('points_march_default', march, '/points', at: Time.utc(2026, 3, 31, 10),
expected: { '#point_830301' => 1 })
      march_doc = Nokogiri::HTML5(File.read(dir.join('points_march_default.html')))
      expect(march_doc.at_css('input[name="start_at"]')['value']).to eq('2026-02-28T00:00')
      point!(march, 830_302, Time.utc(2026, 3, 29, 0, 59, 59))
      point!(march, 830_303, Time.utc(2026, 3, 29, 1))
      capture('points_named_start', march, '/points?start_at=Mar%202026&end_at=2026-03-31T23:59:59Z',
              at: Time.utc(2026, 3, 31, 10), expected: { '#points tbody tr' => 2, '#point_830301' => 0 })
      named_start = Nokogiri::HTML5(File.read(dir.join('points_named_start.html')))
      expect(named_start.at_css('input[name="start_at"]')['value']).to eq('2026-03-01T00:00')
      capture('points_named_end', march, '/points?start_at=2026-02-01T00:00:00Z&end_at=Mar%202026',
              at: Time.utc(2026, 3, 31, 10), expected: { '#points tbody tr' => 1, '#point_830301' => 1 })
      named_end = Nokogiri::HTML5(File.read(dir.join('points_named_end.html')))
      expect(named_end.at_css('input[name="end_at"]')['value']).to eq('2026-03-01T00:00')
      capture('points_berlin_dst', march,
              '/points?start_at=2026-03-29T01:59:59%2B01:00&end_at=2026-03-29T03:00:00%2B02:00',
              at: Time.utc(2026, 3, 31, 10), expected: { '#points tbody tr' => 2 })
      mi = reader(8304, unit: 'mi')
      point!(mi, 830_401, now - 1.hour, velocity: 1.234)
      capture('points_mi', mi, '/points', expected: { '#point_830401' => '2.8' })
      InstanceSetting.where(key: 'photon_api_host').delete_all
      InstanceSettings::Resolver.reset!
      capture('points_geocoding_disabled', owner, '/points', geocoding: false, expected: { 'thead th' => 4 })
      cloud_cases!
    ensure
      travel_back
    end
  end

  def cloud_cases!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('SELF_HOSTED', false)
    stub_const('MANAGER_URL', 'https://manager.a6s3.example.invalid')
    lite = reader(8305, plan: :lite)
    import!(lite, 83_051, 'Old edges.json', now - 10.days)
    [Time.utc(2025, 10, 3, 9, 59, 59), Time.utc(2025, 10, 3, 10),
     Time.utc(2025, 10, 3, 10, 0, 1)].each_with_index do |at, i|
      point!(lite, 830_501 + i, at, import_id: 83_051)
    end
    capture('points_lite', lite, '/points?import_id=83051', geocoding: false,
            expected: { '#points tbody tr' => 2, '#point_830501' => 0, '#point_830502' => 1 })
    lite.update_columns(plan: User.plans[:pro])
    capture('points_cloud_pro', lite.reload, '/points?import_id=83051', geocoding: false,
            expected: { '#points tbody tr' => 3 })
    leap = reader(8306, zone: 'Europe/Berlin', plan: :lite)
    point!(leap, 830_601, Time.utc(2023, 2, 28, 10))
    capture('points_lite_leap', leap, '/points?start_at=2023-02-28T00:00:00Z&end_at=2023-03-01T00:00:00Z',
            at: Time.utc(2024, 2, 29, 10), geocoding: false, expected: { '#point_830601' => 1 })
    dst = reader(8307, zone: 'Europe/Berlin', plan: :lite)
    import!(dst, 83_071, 'DST edges.json', now - 1.day)
    point!(dst, 830_701, Time.utc(2025, 3, 29, 10, 59, 59), import_id: 83_071)
    point!(dst, 830_702, Time.utc(2025, 3, 29, 11), import_id: 83_071)
    capture('points_lite_dst', dst, '/points?import_id=83071', at: Time.utc(2026, 3, 29, 10), geocoding: false,
            expected: { '#point_830701' => 0, '#point_830702' => 1 })
  end

  it 'writes point list and address responses with exact filters' do
    generate!
  end
end
