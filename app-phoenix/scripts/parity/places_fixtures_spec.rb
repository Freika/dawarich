# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_closure_capture'

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

  context 'A8 remaining places' do
    let(:dir) { super().join('remaining') }

    around do |example|
      detailed = Rails.application.env_config['action_dispatch.show_detailed_exceptions']
      Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = false
      example.run
    ensure
      Rails.application.env_config['action_dispatch.show_detailed_exceptions'] = detailed
    end

    before { FileUtils.mkdir_p(dir.join('pages')) }

    def remainder_json(name, data)
      encoded = "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n"
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        File.write(dir.join(name), encoded)
      else
        expect(JSON.parse(dir.join(name).read)).to eq(JSON.parse(encoded))
      end
    end

    def remainder_rows(model, scope)
      scope.order(model.primary_key).map do |row|
        row.attributes.transform_values do |value|
          if value.respond_to?(:utc)
            value.utc.iso8601(6)
          elsif value.is_a?(BigDecimal)
            value.to_s('F')
          elsif value.respond_to?(:coordinates)
            value.coordinates
          else
            value
          end
        end
      end
    end

    def remainder_graph(user, id)
      { places: remainder_rows(Place, Place.where(id: id...id + 20)),
        visits: remainder_rows(Visit, Visit.where(id: id...id + 20)),
        place_visits: remainder_rows(PlaceVisit, PlaceVisit.where(visit_id: id...id + 20)),
        notes: remainder_rows(Note, Note.where(id: id...id + 20)),
        tags: remainder_rows(Tag, Tag.where(id: id...id + 20)),
        taggings: remainder_rows(Tagging, Tagging.where(taggable_type: 'Place', taggable_id: id...id + 20)),
        actor: user_row(user) }
    end

    def remainder_cases
      valid = { name: 'Café <&> Leipzig', latitude: '51.34', longitude: '12.37', source: 'manual', note: "\nPlain <&>" }
      creates = {
        ordinary: valid, default: valid.merge(name: Place::DEFAULT_NAME),
        unicode255: valid.merge(name: '界' * 255), unicode256: valid.merge(name: '界' * 256),
        blank_name: valid.merge(name: ''), missing_name: valid.except(:name),
        blank_lat: valid.merge(latitude: ''), nil_lon: valid.merge(longitude: nil),
        missing_coords: valid.except(:latitude, :longitude), zero: valid.merge(latitude: '0', longitude: '0'),
        photon: valid.merge(source: 'photon'), gpx: valid.merge(source: 'gpx_waypoint'),
        blank_source: valid.merge(source: ''), invalid_source: valid.merge(source: 'bogus'),
        tags: valid.merge(tag_ids: :mixed), empty_tags: valid.merge(tag_ids: [])
      }
      updates = {
        name: { name: 'Edited Café' }, noop: { name: 'Before' }, default: { name: Place::DEFAULT_NAME },
        unicode255: { name: '界' * 255 }, unicode256: { name: '界' * 256 }, blank_name: { name: '' },
        blank_coords: { latitude: '', longitude: '' }, nil_coords: { latitude: nil, longitude: nil },
        coords: { latitude: '51.4', longitude: '12.4' }, zero: { latitude: '0', longitude: '0' },
        source: { source: 'gpx_waypoint' }, blank_source: { source: '' }, invalid_source: { source: 'bogus' },
        note: { note: "\nEdited <&>" }, empty_note: { note: '' }, nil_note: { note: nil },
        omitted_tags: { note: 'Keep tags' }, empty_tags: { tag_ids: [] },
        mixed_tags: { tag_ids: :mixed }, foreign_tags: { tag_ids: :foreign }
      }
      cases = []
      %w[html turbo].each do |format|
        [false, true].each do |framed|
          creates.each do |key, attrs|
            cases << { name: "create_#{key}_#{format}_#{framed}", action: :create, attrs:, format:, framed: }
          end
          updates.each do |key, attrs|
            cases << { name: "update_#{key}_#{format}_#{framed}", action: :update, attrs:, format:, framed: }
          end
          cases << { name: "update_demo_#{format}_#{framed}", action: :update, attrs: { name: 'Adopted' },
                     format:, framed:, demo: true }
          cases << { name: "delete_#{format}_#{framed}", action: :destroy, format:, framed: }
          %i[show update destroy].each do |action|
            cases << { name: "foreign_#{action}_#{format}_#{framed}", action:, format:, framed:, foreign: true,
                       attrs: { name: 'Forbidden' } }
          end
          cases << { name: "show_#{format}_#{framed}", action: :show, format:, framed: }
        end
      end
      { disabled: { latitude: '51.34', longitude: '12.37' }, zero: { latitude: '0', longitude: '0' },
        missing: {}, blank_lat: { latitude: '', longitude: '12.37' },
        missing_lon: { latitude: '51.34' },
        radius: { latitude: '51.34', longitude: '12.37', radius: '1.5', limit: '3' } }
        .each { |key, attrs| cases << { name: "nearby_#{key}", action: :nearby, attrs:, format: 'html' } }
      cases << { name: 'nearby_enabled_zero', action: :nearby, attrs: { latitude: '0', longitude: '0' },
                 format: 'html', provider: true }
      cases << { name: 'create_de_blank_turbo_false', action: :create, attrs: valid.merge(name: ''),
                 format: 'turbo', framed: false, locale: 'de' }
      cases << { name: 'update_de_blank_html_false', action: :update, attrs: { name: '' },
                 format: 'html', framed: false, locale: 'de' }
      cases << { name: 'update_de_long_turbo_false', action: :update, attrs: { name: '界' * 256 },
                 format: 'turbo', framed: false, locale: 'de' }
      cases += cases.select { |entry| entry[:locale] == 'de' }.flat_map do |entry|
        %w[es fr pl ca zh].map do |locale|
          entry.merge(name: entry[:name].sub('_de_', "_#{locale}_"), locale:)
        end
      end
      cases
    end

    def remainder_seed(user, id, entry)
      foreign = reader(user.id + 100_000, 'timezone' => 'Europe/Berlin')
      target = entry[:foreign] ? foreign : user
      place!(target, id, 'Before', demo: entry.fetch(:demo, false), name_locked_at: now - 1.day, note: 'Before note')
      place!(user, id + 1, 'Unrelated')
      tag!(user, id, 'Original', id, now - 1.day, icon: '☕', color: '#aa33cc')
      tag!(user, id + 1, 'Another', id + 1, now - 1.day)
      tag!(foreign, id + 2, 'Foreign', id + 1, now - 1.day)
      visit!(target, id, id, 'Active visit', now - 1.day, 30)
      visit!(target, id + 1, id, 'Tombstoned visit', now - 2.days, 40, deleted_at: now - 1.day)
      visit!(user, id + 2, id + 1, 'Unrelated visit', now - 3.days, 50)
      PlaceVisit.insert!({ id:, visit_id: id, place_id: id, **stamps })
      PlaceVisit.insert!({ id: id + 1, visit_id: id, place_id: id + 1, **stamps })
      Note.insert!({ id:, user_id: target.id, attachable_type: 'Place', attachable_id: id,
                     body: 'Attached note', noted_at: now, **stamps })
      Note.insert!({ id: id + 1, user_id: user.id, body: 'Unrelated note', noted_at: now, **stamps })
      %w[places tags taggings notes place_visits].each do |table|
        sql = "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 10}, false)"
        ActiveRecord::Base.connection.execute(sql)
      end
    end

    def remainder_request(user, id, entry)
      Rails.cache.clear
      reset!
      sign_in user
      get '/settings/visits'
      token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      attrs = entry.fetch(:attrs, {}).dup
      attrs[:tag_ids] = [''] if attrs[:tag_ids] == []
      attrs[:tag_ids] = [id, id + 1, id + 1, id + 2, ''] if attrs[:tag_ids] == :mixed
      attrs[:tag_ids] = [id + 2] if attrs[:tag_ids] == :foreign
      method, path, params = case entry[:action]
                             when :create then [:post, '/places', { place: attrs }]
                             when :update then [:patch, "/places/#{id}", { place: attrs }]
                             when :destroy then [:delete, "/places/#{id}?page=2", {}]
                             when :show then [:get, "/places/#{id}", {}]
                             when :nearby then [:get, '/places/nearby', attrs]
                             end
      accept = entry[:format] == 'turbo' ? 'text/vnd.turbo-stream.html' : 'text/html'
      headers = { 'X-CSRF-Token' => token, 'Accept' => accept }
      headers['Turbo-Frame'] = 'place-drawer' if entry[:framed]
      error = nil
      begin
        public_send(method, path, params:, headers:)
      rescue StandardError => e
        error = e
      end
      [{ method:, path:, params:, accept:, framed: !!entry[:framed], decoded: request.request_parameters }, error]
    end

    def remainder_assert(entry, id, before, after, error)
      name = entry[:name]
      if entry[:foreign]
        expect(response.status).to eq(404), name
        expect(after).to eq(before), name
      elsif entry.dig(:attrs, :source) == 'bogus'
        expect(error).to be_a(ArgumentError), name
        expect(after).to eq(before), name
      elsif entry[:action] == :update && entry[:attrs].key?(:latitude) && entry[:attrs][:latitude].blank?
        expect(error).to be_a(ActiveRecord::NotNullViolation), "#{name}: #{error.inspect}"
        expect(after).to eq(before), name
      elsif entry[:action] == :nearby
        expect(after).to eq(before), name
        missing = entry[:attrs][:latitude].blank? || entry[:attrs][:longitude].blank?
        expect(response.status).to eq(missing ? 400 : 200), name
        expect(response.body).to include('No nearby places found') unless missing
      elsif entry[:action] == :destroy
        expect(error).to be_nil, name
        expect(Place.exists?(id)).to be(false), name
        expect(Tagging.where(taggable_type: 'Place', taggable_id: id)).to be_empty
        expect(Note.exists?(id)).to be(false), name
        expect(PlaceVisit.where(place_id: id)).to be_empty
        expect(after[:visits].first(2)).to eq(before[:visits].first(2).map { _1.merge('place_id' => nil) }), name
        expect(after[:places].find { _1['id'] == id + 1 }).to eq(before[:places].find { _1['id'] == id + 1 }), name
        expect(after[:notes]).to eq(before[:notes].reject { _1['id'] == id }), name
        expect(after[:tags]).to eq(before[:tags]), name
        expect(after[:place_visits]).to eq(before[:place_visits].reject { _1['place_id'] == id }), name
        expect(response.status).to eq(entry[:framed] ? 200 : 303), name
      elsif %i[create update].include?(entry[:action])
        remainder_assert_save(entry, id, before, after, error)
      else
        expect(after).to eq(before), name
        expect(response.status).to eq(entry[:framed] ? 200 : 302), name
      end
    end

    def remainder_assert_save(entry, id, before, after, error)
      attrs = entry[:attrs]
      create = entry[:action] == :create
      invalid = (attrs.key?(:name) && attrs[:name].blank?) || attrs[:name].to_s.length > 255 ||
                (create && (!attrs[:name] || attrs[:latitude].blank? || attrs[:longitude].blank?))
      row = Place.find_by(id: create ? id + 10 : id)
      if invalid
        expect(after).to eq(before), entry[:name]
        expect(row).to be_nil if create
      else
        expect(row).to be_present, entry[:name]
        expect(row.name).to eq(attrs[:name]) if attrs.key?(:name)
        expect(row.name_locked_at).to eq(now) if attrs[:name] && !['Before', Place::DEFAULT_NAME].include?(attrs[:name])
        expect(row.name_locked_at).to be_nil if attrs[:name] == Place::DEFAULT_NAME
        expect(row.name_locked_at).to eq(now - 1.day) if !create && attrs[:name] == 'Before'
        expect(row.demo).to be(false) if entry[:demo]
        expect(row.note).to eq(attrs[:note]) if attrs.key?(:note)
        if attrs.key?(:tag_ids)
          expected = attrs[:tag_ids] == :mixed ? [id, id + 1] : []
          expect(row.tags.order(:id).pluck(:id)).to eq(expected), entry[:name]
        elsif !create
          expect(row.tags.pluck(:id)).to eq([id]), entry[:name]
        end
      end
      if create && entry[:format] == 'html'
        expect(response.status).to eq(406), entry[:name]
      else
        expect(error).to be_nil, entry[:name]
        expect(response.status).to eq(entry[:format] == 'html' ? 303 : 200), entry[:name]
      end
    end

    def remainder_response(entry, error)
      html = error ? '' : scrub(response.body).gsub(/(name="(?:csrf-token|csp-nonce)" content=")[^"]*/, '\1CSRF')
      path = dir.join("pages/#{entry[:name]}.html")
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        File.write(path, html)
      else
        expect(path.read).to eq(html), entry[:name]
      end
      doc = Nokogiri::HTML5.fragment(html)
      { name: entry[:name], status: error ? nil : response.status, media_type: error ? nil : response.media_type,
        headers: error ? {} : response.headers.slice('Content-Type', 'Location', 'Vary', 'Cache-Control'),
        flash: error ? {} : flash.to_hash,
        error: error && { class: error.class.name, message: FixtureRecording.normalize(error.message) },
        streams: doc.css('turbo-stream').map { { action: _1['action'], target: _1['target'] } },
        controls: doc.css('form, input, textarea, button, [data-controller]').map do |node|
          { tag: node.name, attributes: node.attributes.transform_values(&:value) }
        end }
    end

    it 'writes A8 remaining place responses and effects' do
      responses = []
      effects = []
      travel_to now do
        remainder_cases.each_with_index do |entry, index|
          id = 896_000 + index * 20
          user = reader(18_960 + index, 'timezone' => 'Europe/Berlin')
          user.update_columns(settings: user.settings.merge('locale' => entry[:locale])) if entry[:locale]
          user.reload
          remainder_seed(user, id, entry)
          before = remainder_graph(user, id)
          request = error = nil
          RSpec::Mocks.with_temporary_scope do
            configure_instance_geocoding if entry[:provider]
            expect(Geocoding::Search).not_to receive(:call)
            request, error = remainder_request(user, id, entry)
          end
          after = remainder_graph(user, id)
          remainder_assert(entry, id, before, after, error)
          responses << remainder_response(entry, error).merge(request:)
          effects << { name: entry[:name], request:, before:, after: }
        end
        remainder_json('responses.json', { now: now.iso8601, responses: })
        remainder_json('effects.json', { now: now.iso8601, effects: })
        %w[p04 p05].each do |task|
          names = if task == 'p04'
                    %w[create_tags_turbo_false update_omitted_tags_turbo_true
                       update_empty_tags_turbo_true]
                  else
                    %w[delete_html_false delete_turbo_true
                       foreign_destroy_html_false]
                  end
          data = { responses: responses.select { names.include?(_1[:name]) },
                   effects: effects.select { names.include?(_1[:name]) } }
          target = dir.parent.join("a12f3a-#{task}.json")
          encoded = "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2).rstrip}\n"
          if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
            File.write(target, encoded)
          else
            expect(JSON.parse(target.read)).to eq(JSON.parse(encoded))
          end
        end
        %i[create update].each_with_index do |action, index|
          user = reader(98_950 + index, 'timezone' => 'Europe/Berlin')
          id = 989_000 + index * 20
          entry = { action:, demo: true, framed: false, format: action == :create ? 'turbo' : 'html',
                    attrs: { name: 'Rails bounds', latitude: '51.34', longitude: '12.37',
                             tag_ids: ['9223372036854775808'] } }
          remainder_seed(user, id, entry)
          _, error = remainder_request(user, id, entry)
          expect(error).to be_nil
          expect(response.status).to eq(action == :create ? 200 : 303)
          place = Place.find(action == :create ? id + 10 : id)
          expect(place.name).to eq('Rails bounds')
          expect(place.demo).to be(false)
          expect(place.tags).to be_empty
        end
      end
    end
  end

  it 'writes the places list and drawer renders' do
    expect(ENV.fetch('TIME_ZONE', nil)).to be_nil
    expect(DawarichSettings.self_hosted?).to be(true)

    travel_to now do
      seed!
      capture_places_closure
      lists.each { |name, user_id, path| capture_list(name, user_id, path) }
      drawers.each { |name, user_id, place_id| capture_drawer(name, user_id, place_id) }
      closure_write('p01', { cases: %w[list_page1 list_page2 drawer_full drawer_signed_out].map do |name|
        { response: JSON.parse(dir.join("#{name}.json").read), html: dir.join("#{name}.html").read }
      end })
    end
  end
end
