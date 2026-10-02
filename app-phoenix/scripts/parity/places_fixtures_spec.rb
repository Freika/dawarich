# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the places list and drawer as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/places') }
  let(:now) { Time.utc(2026, 10, 2, 10, 0, 0) }
  let(:tables) { %w[places tags taggings visits] }
  let(:frame) { { 'Accept' => 'text/html, application/xhtml+xml', 'Turbo-Frame' => 'place-drawer' } }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before { FileUtils.mkdir_p(dir) }

  def reader(id, settings)
    user = create(:user, id:, email: "a84-#{id}@example.invalid", changelog_consent: :declined)
    merged = user.settings.except('timezone').merge('onboarding_completed' => true).merge(settings)
    user.update_columns(settings: merged, api_key: "a84-k-#{id}", visits_redetected_at: now - 10.days)
    user.reload
  end

  def user_row(user)
    { 'id' => user.id, 'email' => user.email, 'theme' => user.theme, 'settings' => user.settings,
      'admin' => user.admin, 'status' => User.statuses[user.status], 'plan' => User.plans[user.plan],
      'active_until' => user.active_until&.utc&.iso8601(6),
      'subscription_source' => User.subscription_sources[user.subscription_source],
      'changelog_consent' => User.changelog_consents[user.changelog_consent], 'api_key' => user.api_key,
      'visits_redetected_at' => user.visits_redetected_at&.utc&.iso8601(6) }
  end

  def owner(table, id)
    { 'taggings' => "taggable_type = 'Place' AND taggable_id IN (SELECT id FROM places WHERE user_id = #{id})" }
      .fetch(table, "user_id = #{id}")
  end

  def rows(user)
    tables.to_h do |table|
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{owner(table, Integer(user.id))} ORDER BY t.id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def write_json(path, data) = File.write(path, "#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n")

  def stamps(at = now) = { created_at: at, updated_at: at }

  def place!(user, id, name, created: now, north: 0.0, east: 0.0, point: nil, legacy: false, **attrs)
    lat = (51.3397 + north).round(6)
    lon = (12.3731 + east).round(6)
    x, y = point || [lon, lat]
    Place.insert!({ id:, user_id: user.id, name:, latitude: lat, longitude: lon, source: 0,
                    lonlat: legacy ? nil : "POINT(#{x} #{y})" }.merge(attrs).merge(stamps(created)))
  end

  def visit!(user, id, place_id, name, started, minutes, status: :confirmed, deleted_at: nil)
    Visit.insert!({ id:, user_id: user.id, place_id:, name:, started_at: started,
                    ended_at: started + minutes.minutes, duration: minutes, status: Visit.statuses.fetch(status.to_s),
                    deleted_at: }.merge(stamps))
  end

  def tag!(user, id, name, place_id, at, icon: nil, color: nil)
    Tag.insert!({ id:, user_id: user.id, name:, icon:, color: }.merge(stamps))
    Tagging.insert!({ id:, tag_id: id, taggable_type: 'Place', taggable_id: place_id }.merge(stamps(at)))
  end

  def berlin(text) = ActiveSupport::TimeZone['Europe/Berlin'].parse(text).utc

  def seed_owner!
    owner_user = reader(8401, 'timezone' => 'Europe/Berlin')
    place!(owner_user, 840_101, 'Café <b>&</b> "Kowalski"', created: Time.utc(2026, 1, 5, 9, 30), source: 1,
                                                          city: 'Leipzig', country: 'Germany',
                                                          name_locked_at: now - 1.day,
                                                          note: "\nErste Zeile <script>x</script>\nzweite")
    place!(owner_user, 840_102, 'Leerer Ort', created: Time.utc(2026, 7, 15, 9, 30), north: 0.001)
    place!(owner_user, 840_103, 'Wegpunkt', legacy: true, north: 0.001234, east: -0.002345, source: 2,
                                            city: '  ', country: 'Germany', note: 'plain')
    place!(owner_user, 840_104, 'Genau', point: [12.373468123456789, 51.33970012345678])
    (5..23).each do |n|
      place!(owner_user, 840_100 + n, format('Ort %02d', n), created: now - n.hours, east: n * 0.0001)
    end
    tag!(owner_user, 84_011, 'Coffee', 840_101, now - 3.days, icon: '☕', color: '#aa33cc')
    tag!(owner_user, 84_012, 'Work <i>', 840_101, now - 2.days)
    tag!(owner_user, 84_013, 'Spät', 840_101, now - 1.day, icon: '', color: '  ')
    tag!(owner_user, 84_014, 'Waypoint', 840_103, now - 1.day, color: '#123')
    seed_owner_visits!(owner_user)
  end

  def seed_owner_visits!(owner_user)
    visit!(owner_user, 84_101, 840_101, 'Frühstück', berlin('2026-03-28 09:15'), 45)
    visit!(owner_user, 84_102, 840_101, 'Nach der Umstellung', berlin('2026-03-30 09:15'), 135)
    visit!(owner_user, 84_103, 840_101, 'Über Mitternacht', berlin('2026-06-01 23:30'), 45)
    visit!(owner_user, 84_104, 840_101, 'Juni', berlin('2026-06-10 12:00'), 61)
    visit!(owner_user, 84_105, 840_101, 'Juli', berlin('2026-07-10 12:00'), 30)
    visit!(owner_user, 84_106, 840_101, 'August', berlin('2026-08-10 12:00'), 7)
    visit!(owner_user, 84_107, 840_101, 'Gelöscht', berlin('2026-09-10 12:00'), 600, deleted_at: now)
    visit!(owner_user, 84_108, 840_101, 'Abgelehnt', berlin('2026-09-11 12:00'), 600, status: :declined)
    visit!(owner_user, 84_109, 840_101, 'Vorschlag', berlin('2026-09-12 12:00'), 20, status: :suggested)
    visit!(owner_user, 84_110, 840_103, 'Kurz', berlin('2026-05-01 08:00'), 4)
    visit!(owner_user, 84_111, 840_103, 'Kürzer', berlin('2026-05-02 08:00'), 5)
  end

  def seed!
    seed_owner!
    utc = reader(8402, 'timezone' => 'UTC')
    place!(utc, 840_201, 'UTC-Ort', created: Time.utc(2026, 2, 3, 23, 59, 30), city: 'Leipzig')
    place!(utc, 840_202, 'Zweiter', north: 0.002)
    visit!(utc, 84_201, 840_201, 'Spät', Time.utc(2026, 9, 30, 23, 50), 25)
    reader(8403, 'timezone' => 'America/New_York')
    place!(reader(8404, 'timezone' => ''), 840_401, 'Leere Zone', created: Time.utc(2026, 7, 1, 12))
    place!(reader(8405, {}), 840_501, 'Ohne Zone', created: Time.utc(2026, 7, 1, 12))
    foreign = reader(8499, 'timezone' => 'Europe/Berlin')
    place!(foreign, 849_901, 'Fremder Ort', north: 0.003)
    place!(foreign, 849_902, 'Fremd zwei', north: 0.004)
    tag!(foreign, 84_991, 'Fremdes Tag', 849_901, now - 1.day, icon: '🚫')
    visit!(foreign, 84_991, 849_901, 'Fremder Besuch', berlin('2026-09-01 10:00'), 60)
  end

  def lists
    [['list_page1', 8401, '/places'], ['list_page2', 8401, '/places?page=2'],
     ['list_page0', 8401, '/places?page=0'], ['list_page_2abc', 8401, '/places?page=2abc'],
     ['list_page_space', 8401, '/places?page=2+x'], ['list_page_blank', 8401, '/places?page='],
     ['list_page_out', 8401, '/places?page=3'], ['list_extra', 8401, '/places?page=2&view=table'],
     ['list_utc', 8402, '/places'], ['list_empty', 8403, '/places'], ['list_blank_zone', 8404, '/places'],
     ['list_no_zone', 8405, '/places'], ['list_foreign', 8499, '/places']]
  end

  def drawers
    [['drawer_full', 8401, 840_101], ['drawer_empty', 8401, 840_102], ['drawer_gpx', 8401, 840_103],
     ['drawer_utc', 8402, 840_201], ['drawer_signed_out', nil, 840_101]]
  end

  def state(kind, user, path, headers)
    { 'kind' => kind, 'path' => path, 'accept' => headers['Accept'], 'now' => now.iso8601,
      'status' => response.status, 'content_type' => response.media_type, 'vary' => response.headers['Vary'],
      'location' => response.headers['Location'], 'set_cookie' => response.headers['Set-Cookie'].present?,
      'session' => { 'user_return_to' => session[:user_return_to], 'alert' => flash[:alert] },
      'self_hosted' => DawarichSettings.self_hosted?, 'env' => { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
      'user' => user && user_row(user), 'rows' => user ? rows(user) : {} }
  end

  def scrub(html) = html.gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')

  def capture_list(name, user_id, path)
    Rails.cache.clear
    reset!
    user = User.find(user_id)
    sign_in user
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    File.write(dir.join("#{name}.html"), scrub(doc.at_css('body > div.container > div.w-full > div.flex').inner_html))
    write_json(dir.join("#{name}.json"), state('list', user, path, {}).merge('title' => doc.at_css('title').text))
    sign_out user
  end

  def capture_drawer(name, user_id, place_id)
    Rails.cache.clear
    reset!
    user = user_id && User.find(user_id)
    sign_in user if user
    get "/places/#{place_id}", headers: frame
    File.write(dir.join("#{name}.html"), response.status == 200 ? scrub(response.body) : '')
    write_json(dir.join("#{name}.json"), state('drawer', user, "/places/#{place_id}", frame))
    sign_out user if user
  end

  it 'writes the places list and drawer renders' do
    expect(ENV.fetch('TIME_ZONE', nil)).to be_nil
    expect(DawarichSettings.self_hosted?).to be(true)

    travel_to now do
      seed!
      lists.each { |name, user_id, path| capture_list(name, user_id, path) }
      drawers.each { |name, user_id, place_id| capture_drawer(name, user_id, place_id) }
    end
  end
end
