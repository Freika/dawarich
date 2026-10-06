# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the map frames as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_frames') }
  let(:now) { Time.utc(2026, 9, 29, 10, 0, 0) }
  let(:manager_url) { 'https://manager.a6s2-fixture.test' }
  let(:tables) { %w[places areas tags taggings visits place_visits tracks track_segments points stats] }
  let(:accepts) do
    { 'frame' => 'text/html, application/xhtml+xml',
      'stream' => 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml',
      'browser' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'any' => '*/*',
      'none' => '' }
  end

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY')
                                 .and_return('phoenix-a6s2-jwt-fixture-secret-not-for-production')
    FileUtils.mkdir_p(dir)
  end

  def reader(id, timezone: 'Europe/Berlin', plan: :pro, redetected: true, **settings)
    user = create(:user, id:, email: "a6s2-#{id}@dawarich.test", changelog_consent: :declined)
    merged = user.settings.merge('onboarding_completed' => true, 'timezone' => timezone)
                 .merge(settings.deep_stringify_keys)
    user.update_columns(settings: merged, plan: User.plans[plan], status: User.statuses[:active],
                        active_until: Time.utc(3026, 1, 1), api_key: "a6s2-k-#{id}",
                        visits_redetected_at: redetected ? now - 10.days : nil)
    user.reload
  end

  def cloud!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('SELF_HOSTED', false)
    stub_const('MANAGER_URL', manager_url)
  end

  def at(day, time, zone = 'Europe/Berlin') = ActiveSupport::TimeZone[zone].parse("#{day} #{time}").utc

  def stamps = { created_at: now, updated_at: now }

  def place!(user, id, name, east: 0.0, north: 0.0, legacy: false)
    lat = (51.3397 + north).round(6)
    lon = (12.3731 + east).round(6)
    Place.insert!({ id:, user_id: user.id, name:, city: 'Leipzig', country: 'Germany', latitude: lat,
                    longitude: lon, lonlat: legacy ? nil : "POINT(#{lon} #{lat})" }.merge(stamps))
    id
  end

  def tag!(user, id, name, place_id, color: '#aa33cc', icon: nil)
    Tag.insert!({ id:, user_id: user.id, name:, color:, icon: }.merge(stamps))
    Tagging.insert!({ id:, tag_id: id, taggable_type: 'Place', taggable_id: place_id,
                      created_at: now + id.seconds, updated_at: now })
  end

  def area!(user, id, name)
    Area.insert!({ id:, user_id: user.id, name:, latitude: 51.3406, longitude: 12.3816, radius: 120 }.merge(stamps))
    id
  end

  def visit!(user, id, from, to, name: "Visit #{id}", status: :confirmed, place: nil, area: nil,
             confidence: nil, deleted: false)
    Visit.insert!({ id:, user_id: user.id, name:, started_at: from, ended_at: to,
                    duration: ((to - from) / 60).round, status: Visit.statuses[status], place_id: place,
                    area_id: area, confidence:, deleted_at: deleted ? now : nil }.merge(stamps))
    id
  end

  def suggest!(id, visit_id, place_id) = PlaceVisit.insert!({ id:, visit_id:, place_id: }.merge(stamps))

  def track!(user, id, from, to, mode: :walking, distance: 1500, duration: nil, speed: 5.4, gain: nil, loss: nil)
    Track.insert!({ id:, user_id: user.id, start_at: from, end_at: to, distance:,
                    duration: duration || (to - from).to_i, avg_speed: speed,
                    dominant_mode: Track.dominant_modes[mode], elevation_gain: gain, elevation_loss: loss,
                    original_path: 'LINESTRING(12.3731 51.3397, 12.3811 51.3437, 12.3901 51.3402)' }.merge(stamps))
    id
  end

  def segment!(id, track_id, mode, distance, duration, confidence: nil, corrected: false)
    TrackSegment.insert!({ id:, track_id:, transportation_mode: TrackSegment.transportation_modes[mode],
                           distance:, duration:, confidence_score: confidence,
                           corrected_at: corrected ? now : nil, start_index: id, end_index: id + 1 }.merge(stamps))
  end

  def points!(user, first_id, times, visit: nil, country: nil)
    rows = times.each_with_index.map do |time, index|
      { id: first_id + index, user_id: user.id, timestamp: time.to_i, visit_id: visit, country_name: country,
        lonlat: 'POINT(12.3731 51.3397)' }.merge(stamps)
    end
    Point.insert_all!(rows)
  end

  def stat!(user, id, year, month: 1)
    create(:stat, id:, sharing_uuid: "00000000-0000-4000-8000-00000000#{id}", user:, year:, month:,
                  distance: 1000, toponyms: [])
  end

  def owner(table, id)
    { 'taggings' => "taggable_type = 'Place' AND taggable_id IN (SELECT id FROM places WHERE user_id = #{id})",
      'place_visits' => "visit_id IN (SELECT id FROM visits WHERE user_id = #{id})",
      'track_segments' => "track_id IN (SELECT id FROM tracks WHERE user_id = #{id})" }
      .fetch(table, "user_id = #{id}")
  end

  def rows(user)
    tables.to_h do |table|
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{owner(table, Integer(user.id))} ORDER BY t.id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def user_row(user)
    { 'id' => user.id, 'email' => user.email, 'theme' => user.theme, 'settings' => user.settings,
      'admin' => user.admin, 'status' => User.statuses[user.status], 'plan' => User.plans[user.plan],
      'active_until' => user.active_until&.utc&.iso8601(6),
      'subscription_source' => User.subscription_sources[user.subscription_source],
      'changelog_consent' => User.changelog_consents[user.changelog_consent], 'api_key' => user.api_key,
      'visits_redetected_at' => user.visits_redetected_at&.utc&.iso8601(6) }
  end

  def state(user, path, accept)
    { 'path' => path, 'accept' => accepts.fetch(accept), 'now' => now.iso8601, 'status' => response.status,
      'content_type' => response.media_type, 'vary' => response.headers['Vary'],
      'location' => response.headers['Location'],
      'session' => { 'user_return_to' => session[:user_return_to], 'alert' => flash[:alert] },
      'self_hosted' => DawarichSettings.self_hosted?, 'env' => { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
      'user' => user && user_row(user), 'rows' => user ? rows(user) : {} }
  end

  def write_json(path, data) = File.write(path, "#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n")

  def capture(name, user, path, accept: 'frame', as: user)
    Rails.cache.clear
    reset!
    sign_in as if as
    get path, headers: { 'Accept' => accepts.fetch(accept) }
    body = response.body
                   .gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')
                   .gsub(%r{(/auth/dawarich\?token=)[^&"]+}, '\1REDACTED')
    body = '' if response.status >= 400
    raise "#{name} contains a JWT-shaped value" if body.match?(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./)

    File.write(dir.join("#{name}.html"), body)
    write_json(dir.join("#{name}.json"), state(user, path, accept))
    sign_out as if as
  end

  def capture_closure(name, user, requests, write: true)
    cases = requests.map do |path|
      Rails.cache.clear
      reset!
      sign_in user
      before_rows = rows(user)
      begin
        ActiveRecord::Base.transaction(requires_new: true) do
          get path, headers: { 'Accept' => accepts.fetch('frame') }
        end
      rescue ActiveRecord::RangeError, Date::Error, NoMethodError => e
        next { 'path' => path, 'accept' => accepts.fetch('frame'), 'now' => now.iso8601,
          'status' => 500, 'error' => e.class.name, 'body' => '', 'user' => user_row(user), 'rows' => before_rows }
      end
      body = response.body.gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')
                     .gsub(%r{(/auth/dawarich\?token=)[^&"]+}, '\1REDACTED')
      entry = state(user, path, 'frame').merge('body' => body)
      if name == 'm04'
        month = Rack::Utils.parse_query(URI.parse(path).query.to_s).fetch('month')
        entry['calendar_cells'] = Timeline::MonthSummary.new(user:, month:).call[:weeks].flatten
      end
      entry
    end
    data = { 'cases' => cases }
    write_json(dir.join("a12f3a-#{name}.json"), data) if write
    data
  end

  def feed(day, last = day) = "/map/timeline_feeds?start_at=#{day}T00:00:00&end_at=#{last}T23:59:59"

  context 'A8 web visits' do
    let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }

    def a8_visit_graph(users)
      { users: users.map { user_row(_1.reload) },
        rows: (tables + ['notes']).to_h do |table|
          condition = users.map { "(#{owner(table, _1.id)})" }.join(' OR ')
          sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{condition} ORDER BY t.id"
          [table, ActiveRecord::Base.connection.select_values(sql).map { JSON.parse(_1) }]
        end }
    end

    def a8_visit_request(user, method, path, params, accept: 'text/vnd.turbo-stream.html')
      reset!
      sign_in user
      get '/settings/visits'
      token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      clear_enqueued_jobs
      public_send(method, path, params:, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
    end

    def a8_visit_record(name, users, before, request, cache: {})
      target = Rails.root.join('app-phoenix/test/fixtures/a8vv/visits')
      FileUtils.mkdir_p(target)
      body = response.body.gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')
      body = '' if response.status >= 400 && response.media_type == 'text/html'
      File.write(target.join("#{name}.html"), body)
      write_json(target.join("#{name}.json"), {
                   now: now.iso8601, self_hosted: DawarichSettings.self_hosted?, request:, before:,
                   after: a8_visit_graph(users), status: response.status, content_type: response.media_type,
                   location: response.location, flash: flash.to_hash, cache:,
                   headers: response.headers.slice('Content-Type', 'Location', 'Vary', 'Cache-Control',
                                                   'X-Frame-Options', 'Referrer-Policy', 'X-Content-Type-Options'),
                   streams: Nokogiri::HTML5.fragment(body).css('turbo-stream').map { [_1['action'], _1['target']] },
                   jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args] } }
                 })
    end

    def a8_visit_streams
      Nokogiri::HTML5.fragment(response.body).css('turbo-stream').map { [_1['action'], _1['target']] }
    end

    %w[missing_timezone_midnight missing_timezone_dst fractional_final_second lite_cutoff_move
       invalid_confidence_update invalid_confidence_destroy invalid_confidence_merge
       html_update html_destroy html_merge accept_html_preferred
       accept_turbo_preferred].each_with_index do |name, index|
      it "writes A8 review #{name} from Rails" do
        travel_to now do
          Rails.cache.clear
          allow(DawarichSettings).to receive(:self_hosted?).and_return(name != 'lite_cutoff_move')
          user = reader(9300 + index, plan: name == 'lite_cutoff_move' ? :lite : :pro)
          id = 930_000 + index * 10
          visit!(user, id, now - 2.hours, now - 1.hour, name: 'Cafe', status: :suggested)
          visit = Visit.find(id)
          method = :patch
          path = "/visits/#{id}"
          params = { visit: { name: 'Renamed' } }
          accept = 'text/vnd.turbo-stream.html'
          if name.start_with?('missing_timezone_')
            user.update_columns(settings: user.settings.except('timezone'))
            expect(user.reload.safe_settings.timezone).to eq('Europe/Berlin')
            local = name.end_with?('midnight') ? '2026-10-03T00:15:00' : '2026-03-29T03:15:00'
            params[:visit].merge!(started_at: local, ended_at: local.sub('15:00', '45:00'))
          elsif name == 'fractional_final_second'
            params[:visit].merge!(started_at: '2026-10-03T23:59:59.500+02:00',
                                  ended_at: '2026-10-04T00:30:00+02:00')
          elsif name == 'lite_cutoff_move'
            visit.update_columns(started_at: now - 1.year + 30.minutes, ended_at: now - 1.year + 2.hours)
            params[:visit].merge!(started_at: '2025-10-03T09:00:00+02:00', ended_at: '2025-10-03T14:00:00+02:00')
          end
          visit.update_columns(confidence: 101) if name.start_with?('invalid_confidence_')
          if name.end_with?('_destroy')
            method = :delete
            params = {}
          elsif name.end_with?('_merge')
            method = :post
            path = '/visits/merge'
            visit!(user, id + 1, now - 45.minutes, now - 30.minutes, name: 'Park', status: :suggested)
            params = { visit_ids: [id.to_s, (id + 1).to_s] }
          end
          accept = 'text/html' if name.start_with?('html_')
          accept = 'text/html;q=1, text/vnd.turbo-stream.html;q=0' if name == 'accept_html_preferred'
          accept = 'text/html;q=0.5, text/vnd.turbo-stream.html;q=1' if name == 'accept_turbo_preferred'
          before = a8_visit_graph([user])
          a8_visit_request(user, method, path, params, accept:)
          wanted = if name.start_with?('invalid_confidence_')
                     { 'invalid_confidence_update' => 200, 'invalid_confidence_merge' => 422,
                       'invalid_confidence_destroy' => 422 }.fetch(name)
                   elsif name.start_with?('html_') || name == 'accept_html_preferred'
                     method == :delete ? 303 : 302
                   else
                     200
                   end
          expect(response.status).to eq(wanted)
          if name.start_with?('invalid_confidence_')
            expect(a8_visit_graph([user])).to eq(before)
          else
            unless method == :delete
              expect(Visit.find(id).name).to eq(name.end_with?('_merge') ? 'Cafe, Park' : 'Renamed')
            end
            expect(flash.to_hash).to eq({}) if name.start_with?('html_') || name == 'accept_html_preferred'
            if name.start_with?('missing_timezone_')
              expected = name.end_with?('midnight') ? Time.utc(2026, 10, 2, 22, 15) : Time.utc(2026, 3, 29, 1, 15)
              expect(visit.reload.started_at).to eq(expected)
            end
            expect(response.body).to include("visit_entry_#{id}") if %w[fractional_final_second
                                                                        lite_cutoff_move].include?(name)
          end
          a8_visit_record(name, [user], before, { method: method.to_s.upcase, path:, params:, accept: })
        end
      end
    end

    it 'writes A8 visit responses and effects' do
      travel_to now do
        names = %w[soft_delete confirm rename blank_name decline owned_place foreign_area demo_adoption month_move
                   bulk_date bulk_selection bulk_500 bulk_501 bulk_foreign bulk_hidden bulk_archive bulk_source
                   bulk_empty bulk_no_callbacks merge_points merge_cross_day merge_foreign merge_same_place
                   merge_mixed_names bulk_cross_day_destroy soft_delete_turbo]
        names.each_with_index do |name, index|
          Rails.cache.clear
          allow(DawarichSettings).to receive(:self_hosted?).and_return(name != 'bulk_archive')
          user = reader(9001 + index, plan: name == 'bulk_archive' ? :lite : :pro)
          user.update_columns(theme: 'dark')
          id = 900_000 + index * 1000
          visit!(user, id, now - 2.hours, now - 1.hour, name: 'Cafe', status: :suggested)
          visit = Visit.find(id)
          users = [user]
          method = :patch
          path = "/visits/#{id}"
          params = { visit: { status: 'confirmed' } }
          accept = 'text/vnd.turbo-stream.html'
          wanted_status = 200
          cache = {}
          case name
          when 'soft_delete', 'soft_delete_turbo'
            method = :delete
            params = {}
            accept = name == 'soft_delete' ? 'text/html' : 'text/vnd.turbo-stream.html'
            wanted_status = name == 'soft_delete' ? 303 : 200
            points!(user, id, [now - 90.minutes], visit: id)
          when 'rename'
            params = { visit: { name: '  Renamed  ' } }
          when 'blank_name'
            params = { visit: { name: '  ' } }
            accept = 'text/html'
            wanted_status = 302
          when 'decline'
            params = { visit: { name: 'Declined name', status: 'declined' } }
          when 'owned_place', 'demo_adoption'
            place!(user, id, 'Owned cafe')
            params = { visit: { place_id: id.to_s } }
            if name == 'demo_adoption'
              Place.find(id).update_columns(demo: true)
              tag!(user, id, 'Demo cafe', id)
              Tag.find(id).update_columns(demo: true)
              visit.update_columns(demo: true, place_id: id)
            end
          when 'foreign_area'
            other = reader(9100 + index)
            users << other
            area!(other, id, 'Foreign area')
            params = { visit: { area_id: id.to_s } }
            wanted_status = 422
          when 'month_move'
            visit.update_columns(started_at: Time.utc(2026, 9, 30, 20), ended_at: Time.utc(2026, 9, 30, 21))
            params = { visit: { started_at: '2026-10-01T08:00:00+02:00', ended_at: '2026-10-01T09:00:00+02:00' } }
            cache = %w[2026-09-01 2026-10-01].to_h do |month|
              key = Timeline::MonthSummary.cache_key_for(user, Date.parse(month))
              Rails.cache.write(key, 'synthetic stale month')
              [month, key]
            end
          end
          if name.start_with?('bulk_')
            path = '/visits/bulk_update'
            params = { visit_ids: [id.to_s], status: 'confirmed', date: '2026-10-03' }
            case name
            when 'bulk_date'
              visit.update_columns(started_at: Time.utc(2026, 10, 2, 22, 30), ended_at: Time.utc(2026, 10, 2, 23))
              visit!(user, id + 1, Time.utc(2026, 10, 3, 23, 30), Time.utc(2026, 10, 4, 0), status: :suggested)
              params.delete(:visit_ids)
              params[:source_status] = 'suggested'
            when 'bulk_selection'
              visit.update_columns(status: :confirmed)
              params[:visit_ids] = [id.to_s, id.to_s, '0']
              accept = 'text/html'
              wanted_status = 302
            when 'bulk_500', 'bulk_501'
              count = name == 'bulk_500' ? 500 : 501
              (1...count).each do |offset|
                visit!(user, id + offset,
                       now - 2.hours + offset.seconds, now - 1.hour + offset.seconds, status: :suggested)
              end
              params[:visit_ids] = (id...id + count).map(&:to_s)
              wanted_status = 422 if count == 501
            when 'bulk_foreign'
              other = reader(9100 + index)
              users << other
              visit!(other, id + 1, now - 2.hours, now - 1.hour, status: :suggested)
              params[:visit_ids] << (id + 1).to_s
              wanted_status = 404
            when 'bulk_hidden'
              visit!(user, id + 1, now - 2.hours, now - 1.hour, status: :suggested, deleted: true)
              params[:visit_ids] << (id + 1).to_s
              wanted_status = 404
            when 'bulk_archive'
              visit.update_columns(started_at: now - 13.months, ended_at: now - 13.months + 1.hour)
              wanted_status = 404
            when 'bulk_source'
              params[:source_status] = 'confirmed'
              wanted_status = 422
            when 'bulk_empty'
              method = :delete
              path = '/visits/bulk_destroy'
              params = {}
              wanted_status = 422
            when 'bulk_no_callbacks'
              visit.update_columns(demo: true, updated_at: now - 1.day)
            when 'bulk_cross_day_destroy'
              method = :delete
              path = '/visits/bulk_destroy'
              visit!(user, id + 1, now - 1.day - 2.hours, now - 1.day - 1.hour, status: :suggested)
              params = { visit_ids: [id.to_s, (id + 1).to_s] }
            end
          elsif name.start_with?('merge_')
            method = :post
            path = '/visits/merge'
            visit!(user, id + 1, now - 1.hour, now - 30.minutes, name: 'Park', status: :suggested)
            params = { visit_ids: [id.to_s, (id + 1).to_s] }
            case name
            when 'merge_points'
              place!(user, id, 'Suggested cafe')
              suggest!(id, id + 1, id)
              points!(user, id, [now - 45.minutes], visit: id + 1)
            when 'merge_cross_day'
              Visit.find(id + 1).update_columns(started_at: now - 1.day, ended_at: now - 1.day + 1.hour)
              wanted_status = 422
            when 'merge_foreign'
              other = reader(9100 + index)
              users << other
              Visit.find(id + 1).update_columns(user_id: other.id)
              wanted_status = 404
            when 'merge_same_place'
              place!(user, id, 'Same place')
              Visit.where(id: [id, id + 1]).update_all(place_id: id)
            when 'merge_mixed_names'
              visit.update_columns(name: ' Cafe ')
              Visit.find(id + 1).update_columns(name: 'cAFE')
              visit!(user, id + 2, now - 20.minutes, now - 10.minutes, name: 'Park', status: :suggested)
              params[:visit_ids] << (id + 2).to_s
            end
          end
          before = a8_visit_graph(users)
          a8_visit_request(user, method, path, params, accept:)
          expect(response.status).to eq(wanted_status), name
          if wanted_status >= 400
            expect(a8_visit_graph(users)).to eq(before), name
          elsif %w[soft_delete soft_delete_turbo].include?(name)
            expect(Visit.exists?(id)).to be(true)
            expect(Visit.find(id).deleted_at).to eq(now)
            expect(Point.find(id).visit_id).to eq(id)
            if name == 'soft_delete'
              expect(response).to redirect_to('/map/v2?date=today&panel=timeline')
            else
              expect(a8_visit_streams).to eq([['remove', "visit_entry_#{id}"], %w[replace timeline-calendar-frame],
                                              %w[append flash-messages]])
            end
          elsif name.start_with?('merge_')
            expect(Visit.exists?(id + 1)).to be(false)
            merged = Visit.find(id)
            expect(merged.status).to eq('confirmed')
            expect(merged.started_at).to eq(now - 2.hours)
            expect(merged.ended_at).to eq(name == 'merge_mixed_names' ? now - 10.minutes : now - 30.minutes)
            expect(merged.duration).to eq(name == 'merge_mixed_names' ? 110 : 90)
            expect(merged.name).to eq({ 'merge_same_place' => 'Cafe', 'merge_mixed_names' => ' Cafe , Park' }.fetch(
                                        name, 'Cafe, Park'
                                      ))
            if name == 'merge_points'
              expect(Point.find(id).visit_id).to eq(id)
              expect(PlaceVisit.where(visit_id: id + 1)).to be_empty
            end
            expect(a8_visit_streams).to eq([%w[update timeline-feed-frame], %w[append flash-messages]])
          elsif name == 'bulk_cross_day_destroy'
            expect(Visit.where(id: [id, id + 1]).pluck(:deleted_at)).to eq([now, now])
            expect(a8_visit_streams).to eq([%w[replace timeline-calendar-frame], %w[append flash-messages]])
          elsif name.start_with?('bulk_')
            expect(visit.reload.status).to eq('confirmed')
            expect(Visit.find(id + 1).status).to eq('suggested') if name == 'bulk_date'
            expect(user.visits.where(status: :confirmed).count).to eq(500) if name == 'bulk_500'
            if name == 'bulk_no_callbacks'
              expect(visit.demo?).to be(true)
              expect(visit.updated_at).to eq(now - 1.day)
            end
            if accept == 'text/html'
              expect(response).to redirect_to('/map/v2?date=2026-10-03&panel=timeline&status=suggested')
            else
              expect(a8_visit_streams).to eq([%w[update timeline-feed-frame], %w[replace timeline-calendar-frame],
                                              %w[append flash-messages]])
            end
          else
            visit.reload
            expect(visit.status).to eq(name == 'decline' ? 'declined' : 'confirmed')
            wanted_name = { 'rename' => 'Renamed', 'decline' => 'Declined name',
                            'owned_place' => 'Owned cafe', 'demo_adoption' => 'Owned cafe' }.fetch(name, 'Cafe')
            expect(visit.name).to eq(wanted_name)
            expect(visit.duration).to eq(60)
            if name == 'demo_adoption'
              expect([visit.demo?, Place.find(id).demo?, Tag.find(id).demo?]).to eq([false, false, false])
            end
            if accept == 'text/html'
              expect(response).to redirect_to('/map/v2?date=today&panel=timeline&status=suggested')
            else
              expect(a8_visit_streams).to eq([['replace', "visit_entry_#{id}"], %w[replace timeline-calendar-frame],
                                              %w[append flash-messages]])
            end
          end
          cache = cache.transform_values { Rails.cache.exist?(_1) }
          expect(cache.values).to eq([false, false]) if name == 'month_move'
          a8_visit_record(name, users, before, { method: method.to_s.upcase, path:, params:, accept: }, cache:)
        end
      end
    end

    it 'writes A8 explicitly suggested foreign place selection' do
      travel_to now do
        user = reader(9201)
        other = reader(9202)
        place!(other, 920_001, 'Suggested foreign cafe')
        visit!(user, 920_001, now - 2.hours, now - 1.hour, name: 'Unmatched', status: :suggested)
        suggest!(920_001, 920_001, 920_001)
        visit = Visit.find(920_001)
        expect(Place.find(920_001).user_id).to eq(other.id)
        expect(visit.suggested_places.pluck(:id)).to eq([920_001])
        params = { visit: { place_id: '920001' } }
        before = a8_visit_graph([user, other])
        a8_visit_request(user, :patch, '/visits/920001', params)
        expect(response.status).to eq(200)
        expect(visit.reload.place_id).to eq(920_001)
        expect(visit.name).to eq('Suggested foreign cafe')
        expect(visit.status).to eq('confirmed')
        a8_visit_record('suggested_foreign_place', [user, other], before,
                        { method: 'PATCH', path: '/visits/920001', params:, accept: 'text/vnd.turbo-stream.html' })
      end
    end

    it 'writes A8 noted merge dependent deletion graph' do
      travel_to now do
        user = reader(9210)
        place!(user, 921_001, 'Noted cafe')
        visit!(user, 921_001, now - 2.hours, now - 1.hour, name: 'Cafe', status: :suggested)
        visit!(user, 921_002, now - 1.hour, now - 30.minutes, name: 'Park', status: :suggested)
        suggest!(921_001, 921_002, 921_001)
        Note.create!(id: 921_001, user:, attachable: Visit.find(921_002), body: 'Synthetic visit note', noted_at: now)
        expect(Note.where(attachable_type: 'Visit', attachable_id: 921_002).count).to eq(1)
        params = { visit_ids: %w[921001 921002] }
        before = a8_visit_graph([user])
        a8_visit_request(user, :post, '/visits/merge', params)
        expect(response.status).to eq(200)
        expect(Visit.exists?(921_002)).to be(false)
        expect(Note.exists?(921_001)).to be(false)
        expect(PlaceVisit.exists?(921_001)).to be(false)
        expect(a8_visit_streams).to eq([%w[update timeline-feed-frame], %w[append flash-messages]])
        a8_visit_record('merge_noted', [user], before,
                        { method: 'POST', path: '/visits/merge', params:, accept: 'text/vnd.turbo-stream.html' })
      end
    end
  end

  it 'writes the self-hosted day feeds' do
    travel_to now do
      rich = reader(7101)
      cafe = place!(rich, 7201, 'Café Kowalski, Karl-Liebknecht-Straße, 10, Leipzig, Sachsen', east: 0.002)
      park = place!(rich, 7202, 'Clara-Zetkin-Park', east: -0.01, north: -0.005)
      bakery = place!(rich, 7203, 'Bäckerei Kleinert', east: 0.003, legacy: true)
      twin = place!(rich, 7204, ' bäckerei kleinert ', east: 0.0031)
      tag!(rich, 7701, 'Coffee', cafe, icon: '☕')
      tag!(rich, 7702, 'Work', cafe, color: nil)
      station = area!(rich, 7801, 'Hauptbahnhof')
      d = '2026-09-27'
      track!(rich, 7401, at(d, '07:10'), at(d, '08:00'), mode: :walking, distance: 2400)
      segment!(7501, 7401, :walking, 1800, 1500, confidence: 0.9)
      segment!(7502, 7401, :cycling, 600, 300, confidence: 0.4)
      visit!(rich, 7301, at(d, '08:05'), at(d, '09:40'), name: '', place: cafe)
      track!(rich, 7402, at(d, '09:45'), at(d, '10:05'), mode: :cycling, distance: 3200, duration: 1200)
      segment!(7503, 7402, :cycling, 3000, 500)
      segment!(7504, 7402, :walking, 200, 100, confidence: 0.2, corrected: true)
      visit!(rich, 7302, at(d, '10:10'), at(d, '11:30'), status: :suggested, place: bakery, confidence: 55)
      suggest!(7901, 7302, twin)
      suggest!(7902, 7302, park)
      track!(rich, 7403, at(d, '11:35'), at(d, '12:00'), mode: :stationary, distance: 150)
      track!(rich, 7404, at(d, '11:40'), at(d, '11:50'), mode: :stationary, distance: 40)
      visit!(rich, 7303, at(d, '13:30'), at(d, '14:10'), status: :suggested, area: station, confidence: 20)
      visit!(rich, 7304, at(d, '15:00'), at(d, '16:00'), name: 'Wohnung')
      visit!(rich, 7305, at(d, '16:30'), at(d, '17:00'), status: :declined)
      visit!(rich, 7306, at(d, '17:30'), at(d, '18:00'), deleted: true)
      points!(rich, 7601, [at(d, '08:10'), at(d, '08:40'), at(d, '09:20')], visit: 7301)
      points!(rich, 7611, [at(d, '10:20'), at(d, '11:00')], visit: 7302)
      capture('feed_rich_en', rich, feed(d))
      visit!(rich, 7307, at(d, '08:05'), at(d, '09:40'), name: 'Same-time stop')
      capture_closure('m03', rich, [
                        feed(d), '/map/timeline_feeds',
                        '/map/timeline_feeds?start_at=garbage&end_at=garbage',
                        '/map/timeline_feeds?start_at[]=1&end_at=2', "#{feed(d)}&locale=de"
                      ])
      Visit.where(id: 7307).delete_all

      night = reader(7102)
      track!(night, 7411, at('2026-09-27', '22:30'), at('2026-09-28', '01:30'), mode: :driving, distance: 60_000,
                                                                             speed: 55.0)
      segment!(7511, 7411, :driving, 58_000, 9000, confidence: 0.95)
      visit!(night, 7311, at('2026-09-28', '00:00'), at('2026-09-28', '23:45'), name: 'Hotel Fürstenhof')
      capture('feed_midnight_en', night, feed('2026-09-27', '2026-09-28'))

      legacy = reader(7103, redetected: false, maps: { 'distance_unit' => 'mi' })
      visit!(legacy, 7321, at(d, '09:00'), at(d, '10:00'), name: 'Zoo Leipzig')
      visit!(legacy, 7322, at(d, '11:00'), at(d, '12:00'), status: :suggested, confidence: 10)
      track!(legacy, 7421, at(d, '12:05'), at(d, '12:35'), mode: :driving, distance: 16_093, speed: 32.2)
      capture('feed_legacy_mi_en', legacy, feed(d))

      wide = reader(7106)
      visit!(wide, 7331, at('2026-09-10', '09:00'), at('2026-09-10', '10:00'))
      capture('feed_range_en', wide, '/map/timeline_feeds?start_at=2026-08-27T00:00:00&end_at=2026-09-28T00:00:00')

      epoch = reader(7107)
      visit!(epoch, 7341, at(d, '09:00'), at(d, '10:00'), name: 'Nikolaikirche')
      capture('feed_epoch_en', epoch,
              "/map/timeline_feeds?start_at=#{at(d, '00:00').to_i}&end_at=#{at(d, '23:59:59').to_i}")

      dst = reader(7108)
      track!(dst, 7451, at('2026-10-24', '23:00'), at('2026-10-25', '04:00'), mode: :train, distance: 180_000)
      capture('feed_dst_en', dst, feed('2026-10-24', '2026-10-25'))

      havana = reader(7109, timezone: 'America/Havana')
      track!(havana, 7461, at('2026-03-07', '22:00', 'America/Havana'), at('2026-03-08', '03:00', 'America/Havana'),
             mode: :bus, distance: 40_000)
      capture('feed_havana_en', havana, feed('2026-03-07', '2026-03-08'))

      tokyo = reader(7110, timezone: 'Asia/Tokyo')
      visit!(tokyo, 7371, Time.utc(2026, 1, 15, 23, 30), Time.utc(2026, 1, 16, 1, 0), name: 'Shibuya Sky')
      capture('feed_tokyo_en', tokyo, feed('2026-01-16'))

      capture('feed_signed_out', nil, feed(d))
    end
  end

  it 'writes the Cloud day feeds' do
    travel_to now do
      cloud!
      empty = reader(7104, plan: :lite)
      capture('feed_empty_lite_en', empty, feed('2026-09-27'))

      window = reader(7105, plan: :lite)
      visit!(window, 7351, at('2025-09-29', '11:00'), at('2025-09-29', '11:30'), name: 'Vor dem Fenster')
      visit!(window, 7352, at('2025-09-29', '13:00'), at('2025-09-29', '13:30'), name: 'Im Fenster')
      capture('feed_window_lite_en', window, feed('2025-09-29'))
    end
  end

  it 'writes the track cards' do
    travel_to now do
      km = reader(7111)
      track!(km, 7481, at('2026-09-27', '07:00'), at('2026-09-27', '08:00'), mode: :cycling, distance: 12_345,
                                                                           speed: 18.47, gain: 120, loss: 95)
      capture('track_km_en', km, '/map/timeline_feeds/7481/track_info')
      capture_closure('m05', km, ['/map/timeline_feeds/7481/track_info',
                                  '/map/timeline_feeds/7481/track_info?locale=de'])

      mi = reader(7112, maps: { 'distance_unit' => 'mi' })
      track!(mi, 7482, at('2026-09-27', '07:00'), at('2026-09-27', '07:30'), mode: :unknown, distance: 800,
                                                                           speed: 18.47)
      capture('track_mi_en', mi, '/map/timeline_feeds/7482/track_info')

      other = reader(7118)
      track!(other, 7483, at('2026-09-27', '07:00'), at('2026-09-27', '07:30'))
      capture('track_foreign', km, '/map/timeline_feeds/7483/track_info')
      capture('track_signed_out', nil, '/map/timeline_feeds/7481/track_info')
    end
  end

  it 'writes the calendars' do
    travel_to now do
      cal = reader(7113)
      visit!(cal, 7381, at('2026-09-03', '10:00'), at('2026-09-03', '12:00'), name: 'Bibliotheca Albertina')
      visit!(cal, 7382, at('2026-09-10', '10:00'), at('2026-09-10', '11:00'), status: :suggested)
      visit!(cal, 7383, at('2026-09-05', '09:00'), at('2026-09-05', '12:00'))
      visit!(cal, 7384, at('2026-09-07', '09:00'), at('2026-09-07', '14:00'))
      visit!(cal, 7385, at('2026-09-08', '09:00'), at('2026-09-08', '17:00'))
      track!(cal, 7491, at('2026-09-15', '08:00'), at('2026-09-15', '20:00'), mode: :walking, distance: 9000)
      track!(cal, 7492, at('2026-09-20', '23:00'), at('2026-09-21', '01:00'), mode: :driving, distance: 30_000)
      track!(cal, 7493, at('2026-08-31', '22:00'), at('2026-09-01', '02:00'), mode: :train, distance: 90_000)
      track!(cal, 7494, at('2026-10-25', '00:30'), at('2026-10-25', '05:00'), mode: :driving, distance: 50_000)
      points!(cal, 7621, [at('2026-09-25', '12:00')])
      capture('calendar_frame_en', cal, '/map/timeline_feeds/calendar?month=2026-09')
      visit!(cal, 7499, at('2026-10-01', '12:00'), at('2026-10-01', '13:00'))
      capture_closure('m04', cal, [
                        '/map/timeline_feeds/calendar?month=2026-09',
                        '/map/timeline_feeds/calendar?month=2026-9',
                        '/map/timeline_feeds/calendar?month[]=2026-09'
                      ])
      Visit.where(id: 7499).delete_all
      capture('calendar_stream_en', cal, '/map/timeline_feeds/calendar?month=2026-10', accept: 'stream')
      capture('calendar_any_en', cal, '/map/timeline_feeds/calendar?month=2026-09', accept: 'any')
      capture('calendar_browser_en', cal, '/map/timeline_feeds/calendar?month=2026-09', accept: 'browser')
      capture('calendar_none_en', cal, '/map/timeline_feeds/calendar?month=2026-09', accept: 'none')
      capture('calendar_blank_month_en', cal, '/map/timeline_feeds/calendar?month=')
      capture('calendar_signed_out_stream', nil, '/map/timeline_feeds/calendar?month=2026-09', accept: 'stream')
    end
  end

  it 'writes the Cloud calendar' do
    travel_to now do
      cloud!
      lite = reader(7114, plan: :lite)
      visit!(lite, 7391, at('2025-09-30', '10:00'), at('2025-09-30', '11:00'), name: 'Auerbachs Keller')
      capture('calendar_lite_en', lite, '/map/timeline_feeds/calendar?month=2025-09')
    end
  end

  it 'writes the residency frames' do
    travel_to now do
      pro = reader(7115)
      stat!(pro, 7915, 2026)
      day = ->(date) { Time.utc(date.year, date.month, date.day, 12) }
      stays = { 'Germany' => [Date.new(2026, 1, 1)..Date.new(2026, 7, 2)],
                'Czechia' => [Date.new(2026, 7, 10)..Date.new(2026, 7, 14),
                              Date.new(2026, 7, 18)..Date.new(2026, 7, 20)],
                'Poland' => [Date.new(2026, 7, 21)..Date.new(2026, 7, 27)],
                'Austria' => [Date.new(2026, 8, 1)..Date.new(2026, 8, 6)],
                'France' => [Date.new(2026, 8, 10)..Date.new(2026, 8, 14)],
                'Italy' => [Date.new(2026, 8, 15)..Date.new(2026, 8, 18)],
                'Spain' => [Date.new(2026, 8, 20)..Date.new(2026, 8, 22)],
                'Netherlands' => [Date.new(2026, 9, 1)..Date.new(2026, 9, 2)],
                'Atlantis' => [Date.new(2026, 9, 5)..Date.new(2026, 9, 5)] }
      next_id = 80_000
      stays.each do |country, ranges|
        times = ranges.flat_map(&:to_a).map(&day)
        points!(pro, next_id, times, country:)
        next_id += times.size
      end
      capture('residency_pro_en', pro, '/map/residency?year=2026')

      empty = reader(7116)
      capture('residency_empty_en', empty, '/map/residency?year=2025')

      default = reader(7117)
      stat!(default, 7917, 2024, month: 5)
      stat!(default, 7918, 2025, month: 5)
      points!(default, 81_000, [Time.utc(2025, 5, 1, 12), Time.utc(2025, 5, 2, 12)], country: 'Germany')
      capture('residency_default_year_en', default, '/map/residency')

      capture('residency_signed_out', nil, '/map/residency?year=2026')
      tied = reader(7991)
      points!(tied, 7992, [at('2026-03-21', '12:00')], country: 'Germany')
      points!(tied, 7993, [at('2026-03-22', '12:00')], country: 'Czechia')
      points!(tied, 7994, [at('2026-03-21', '13:00')], country: 'Czechia')
      points!(tied, 7995, [at('2026-03-22', '13:00')], country: 'Germany')
      data = capture_closure('m06', tied, ['/map/residency?year=2026', '/map/residency?year=2026tail',
                                           '/map/residency?year=2038', '/map/residency?year[]=2026'])
      cloud!
      lite = reader(7999, plan: :lite)
      data['access_cases'] =
        capture_closure('m06-access', lite, ['/map/residency?year=not-valid'], write: false)['cases']
      write_json(dir.join('a12f3a-m06.json'), data)
    end
  end
end
