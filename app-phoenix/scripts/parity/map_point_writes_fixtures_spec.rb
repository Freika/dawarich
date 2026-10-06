# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: map point writes', type: :request do
  source_cases = {}
  define_method(:source_case) do |name, data|
    source_cases[name] = data.merge('user' => data.fetch('user').merge('api_key' => 'API_KEY'))
  end
  after(:all) do
    selected = source_cases.sort.to_h.select { |name, _| [''].any? { name.start_with?(_1) } }
    unless selected.empty?
      FixtureRecording.source_verify(Rails.root.join('app-phoenix/test/fixtures/map_writes/a12f3a-w03.json'),
                                     "#{JSON.pretty_generate(selected)}\n")
    end
    selected = source_cases.sort.to_h.select { |name, _| [''].any? { name.start_with?(_1) } }
    unless selected.empty?
      FixtureRecording.source_verify(Rails.root.join('app-phoenix/test/fixtures/map_writes/a12f3a-w04.json'),
                                     "#{JSON.pretty_generate(selected)}\n")
    end
  end

  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_writes/points') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:accept) { 'text/html, application/xhtml+xml' }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before { FileUtils.mkdir_p(dir) }

  def reader(id, zone: 'UTC', plan: :pro)
    create(:user, id:, email: "a6s4-point-#{id}@example.invalid", theme: 'light', plan:,
                  changelog_consent: :declined, created_at: now, updated_at: now).tap do |user|
      user.update_columns(api_key: "a6s4-synthetic-#{id}", visits_redetected_at: now - 10.days,
                          settings: user.settings.merge('onboarding_completed' => true, 'timezone' => zone))
      user.reload
    end
  end

  def seed(user, foreign, id)
    Track.insert!({ id:, user_id: user.id, start_at: Time.utc(2025, 12, 31, 23, 30), end_at: now,
                    original_path: 'LINESTRING(12.3 51.3, 12.4 51.4)', distance: 1000, duration: 600,
                    avg_speed: 6, created_at: now - 1.day, updated_at: now - 1.day })
    Import.insert!({ id:, user_id: user.id, name: 'Synthetic.json', points_count: 3,
                     created_at: now - 1.day, updated_at: now - 1.day })
    Import.insert!({ id: id + 1, user_id: user.id, name: 'Synthetic-other.json', points_count: 1,
                     created_at: now - 1.day, updated_at: now - 1.day })
    times = [Time.utc(2025, 12, 31, 23, 30), Time.utc(2025, 12, 31, 23, 45),
             Time.utc(2026, 1, 1, 0, 15), Time.utc(2026, 2, 1), now - 1.hour]
    times.each_with_index do |at, index|
      Point.insert!({ id: id + index, user_id: user.id, timestamp: at.to_i,
                      track_id: index < 3 ? id : nil, import_id: if index < 3
                                                                   id
                                                                 else
                                                                   index == 3 ? id + 1 : nil
                                                                 end,
                      lonlat: 'POINT(12.373468 51.339700)', created_at: now - 1.day, updated_at: now - 1.day })
    end
    Point.insert!({ id: id + 9, user_id: foreign.id, timestamp: now.to_i,
                    lonlat: 'POINT(12.373468 51.339700)', created_at: now - 1.day, updated_at: now - 1.day })
    user.update_columns(points_count: 5)
    foreign.update_columns(points_count: 1)
  end

  def graph(user, foreign)
    owners = [user.id, foreign.id].join(',')
    counters = [user.reload, foreign.reload].map do |actor|
      actor.attributes.slice('id', 'points_count', 'updated_at').transform_values do |value|
        value.is_a?(Time) ? value.utc.iso8601(6) : value
      end
    end
    %w[points imports tracks].to_h do |table|
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE user_id IN (#{owners}) ORDER BY id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { JSON.parse(_1) }]
    end.merge('users' => counters)
  end

  def cases
    %w[empty blank duplicate unmatched foreign mixed all untracked import_one timezone_month year_boundary
       lite_old filter_start filter_end filter_order filter_import query_precedence override_delete guest]
  end

  def selection(name, id)
    case name
    when 'empty' then nil
    when 'blank' then ['', ' ', '　']
    when 'unmatched' then [(id + 8).to_s]
    when 'foreign' then [(id + 9).to_s]
    when 'mixed' then ['', id.to_s, id.to_s, (id + 9).to_s]
    when 'duplicate' then [id.to_s, id.to_s, (id + 1).to_s]
    when 'all', 'timezone_month', 'year_boundary' then (id...id + 5).map(&:to_s)
    when 'untracked' then [(id + 4).to_s]
    when 'import_one' then [(id + 3).to_s]
    else [id.to_s]
    end
  end

  def capture(name, index)
    user = reader(9500 + index * 2, zone: name == 'timezone_month' ? 'Europe/Berlin' : 'UTC',
                                  plan: name == 'lite_old' ? :lite : :pro)
    foreign = reader(9501 + index * 2)
    id = 950_000 + index * 10
    seed(user, foreign, id)
    Rails.cache.clear
    clear_achievement_checks(user.id)
    reset!
    sign_in user unless name == 'guest'
    get(name == 'guest' ? '/users/sign_in' : '/tags/new')
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    params = { page: '9' }
    ids = selection(name, id)
    params[:point_ids] = ids if ids
    filters = { 'filter_start' => { start_at: '2026-10-03T00:00:00Z' },
                'filter_end' => { end_at: '2026-10-03T23:59:59Z' },
                'filter_order' => { order_by: 'asc' }, 'filter_import' => { import_id: (id + 1).to_s },
                'query_precedence' => { start_at: 'body', end_at: 'end', order_by: 'asc', import_id: id.to_s } }
              .fetch(name, {})
    params.merge!(filters)
    method = name == 'override_delete' ? :post : :delete
    params[:_method] = 'delete' if method == :post
    path = '/points/bulk_destroy'
    path += '?start_at=query&order_by=desc&page=4' if name == 'query_precedence'
    before = graph(user, foreign)
    before_session = { 'flash' => session['flash'], 'csrf_present' => session[:_csrf_token].present? }
    @epochs = []
    @achievements = []
    allow(Points::TileEpoch).to receive(:bump) { |actor_id, timestamps:| @epochs << { 'user_id' => actor_id, 'timestamps' => timestamps } }
    allow(Achievements::CheckJob).to receive(:schedule).and_wrap_original do |original, actor_id, oldest_timestamp:|
      @achievements << { 'user_id' => actor_id, 'oldest_timestamp' => oldest_timestamp }
      original.call(actor_id, oldest_timestamp:)
    end
    clear_enqueued_jobs
    RSpec::Mocks.with_temporary_scope do
      if name == 'lite_old'
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        stub_const('SELF_HOSTED', false)
      end
      public_send(method, path, params:, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
    end
    expect(response.status).to eq(name == 'guest' ? 302 : 303), name
    after = graph(user, foreign)
    assert_change(name, user, foreign, id, ids, before, after)
    unless name == 'guest'
      query = Rack::Utils.parse_query(URI(response.location).query)
      expect(query).not_to have_key('page')
      expected = filters.stringify_keys
      expected.merge!('start_at' => 'query', 'order_by' => 'desc') if name == 'query_precedence'
      expect(query).to eq(expected), name
      empty = %w[empty blank].include?(name)
      key = empty ? 'no_points_selected' : 'points_were_successfully_destroyed'
      expect(flash[empty ? :alert : :notice]).to eq(I18n.t("controllers.points.#{key}")), name
    end
    state = { 'now' => now.iso8601(6), 'request' => { 'method' => method.to_s.upcase, 'path' => path,
                                                   'params' => params.deep_stringify_keys, 'accept' => accept },
              'user' => user.attributes.slice('id', 'email', 'theme', 'settings', 'api_key', 'plan', 'status'),
              'before' => before, 'after' => after, 'status' => response.status,
              'content_type' => response.media_type, 'vary' => response.headers['Vary'],
              'location' => response.location,
              'flash' => flash.to_hash, 'session_before' => before_session,
              'session_after' => { 'flash' => session['flash'], 'csrf_present' => session[:_csrf_token].present? },
              'set_cookie' => response.headers['Set-Cookie'].present?,
              'epochs' => @epochs, 'achievements' => @achievements,
              'pending_oldest' => Achievements::PendingChecks.read(user.id).first,
              'jobs' => enqueued_jobs.map { { 'job' => _1[:job].name, 'args' => _1[:args], 'queue' => _1[:queue] } } }
    File.write(dir.join("#{name}.html"), '')
    token_pattern = /(name="(?:authenticity_token|csrf-token|csp-nonce)" (?:value|content)=")[^"]*/
    source_body = FixtureRecording.normalize(response.body).gsub(token_pattern, '\\1CSRF')
                                  .gsub(/(nonce=")[^"]*/, '\\1NONCE')
                                  .gsub(/(signed-stream-name=")[^"]*/, '\\1SIGNED')
    source_case(name, state.merge('body' => source_body))
    File.write(dir.join("#{name}.json"), "#{Oj.dump(state, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  def assert_change(name, user, foreign, id, ids, before, after)
    deleted = name == 'guest' ? [] : Array(ids).map(&:to_i).uniq & (id...id + 5).to_a
    expect(user.reload.points_count).to eq(5 - deleted.size), name
    expect(foreign.reload.points_count).to eq(1), name
    expect(user.points.order(:id).pluck(:id)).to eq((id...id + 5).to_a - deleted), name
    jobs = enqueued_jobs.map { [_1[:job].name, _1[:args]] }
    if deleted.empty?
      expect(after).to eq(before), name
      expect(jobs).to be_empty, name
      expect(@epochs).to be_empty, name
      expect(@achievements).to be_empty, name
      return
    end
    rows = before['points'].select { deleted.include?(_1['id']) }
    zone = ActiveSupport::TimeZone[user.timezone]
    months = rows.map { zone.at(_1['timestamp']) }.map { [_1.year, _1.month] }.uniq
    expect(jobs.select { _1.first == 'Stats::CalculatingJob' }.map(&:last)).to match_array(months.map {
      [user.id, *_1]
    }), name
    tracks = rows.filter_map { _1['track_id'] }.uniq
    expect(jobs.select { _1.first == 'Tracks::RecalculateJob' }.map(&:last)).to eq(tracks.map { [_1] }), name
    expect(jobs.select { _1.first == 'Achievements::CheckJob' }.map(&:last)).to eq([[user.id]]), name
    oldest = rows.map { _1['timestamp'] }.min
    expect(@achievements).to eq([{ 'user_id' => user.id, 'oldest_timestamp' => oldest }]), name
    expect(@epochs).to eq([{ 'user_id' => user.id, 'timestamps' => rows.map { _1['timestamp'] } }]), name
    expect(Achievements::PendingChecks.read(user.id).first).to eq(oldest), name
    before['imports'].each do |import|
      count = rows.count { _1['import_id'] == import['id'] }
      expect(Import.find(import['id']).points_count).to eq(import['points_count'] - count), name
    end
  end

  def capture_api_closure!
    ActionController::Base.allow_forgery_protection = false
    user = reader(9890)
    foreign = reader(9891)
    id = 989_000
    seed(user, foreign, id)
    headers = { 'Authorization' => "Bearer #{user.api_key}", 'Accept' => 'application/json' }
    records = []
    requests = [[:delete, '/api/v1/points/bulk_destroy', {}],
                [:delete, '/api/v1/points/bulk_destroy', { point_ids: [(id + 9).to_s] }],
                [:patch, "/api/v1/points/#{id + 9}", { point: { latitude: '1', longitude: '2' } }],
                [:patch, "/api/v1/points/#{id + 4}", { point: { latitude: '50', longitude: '14', timestamp: 1 } }],
                [:patch, "/api/v1/points/#{id + 4}/position", { point: { latitude: '51', longitude: '15', revision: 0 },
                  history_scope: { start_at: '2026-01-01T10:30Z', end_at: '2026-10-03T10:00Z' } }],
                [:post, '/api/v1/points/reapply_anomaly_filter', {}],
                [:post, '/api/v1/points/reapply_anomaly_filter', {}],
                [:delete, '/api/v1/points/bulk_destroy', { point_ids: [id.to_s, (id + 9).to_s] }]]
    Rails.cache.clear
    requests.each do |method, path, params|
      clear_enqueued_jobs
      public_send(method, path, params:, headers:)
      records << { method:, path:, params:, status: response.status, body: response.body,
                   jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args] } },
                   own_count: user.reload.points_count, foreign_count: foreign.reload.points_count }
    end
    RSpec::Mocks.with_temporary_scope do
      config = Rails.application.env_config.merge('action_dispatch.show_exceptions' => :all,
                                                  'action_dispatch.show_detailed_exceptions' => false)
      allow(Rails.application).to receive(:env_config).and_return(config)
      allow(Achievements::CheckJob).to receive(:schedule).and_raise('synthetic producer failure')
      patch "/api/v1/points/#{id + 4}", params: { point: { latitude: '53', longitude: '16' } },
                                       headers:, env: { 'action_dispatch.show_exceptions' => :all }
      records << { name: 'relocation_callback_failure', status: response.status, body: response.body,
                   position: Point.find(id + 4).lonlat.as_text }
    end
    RSpec::Mocks.with_temporary_scope do
      config = Rails.application.env_config.merge('action_dispatch.show_exceptions' => :all,
                                                  'action_dispatch.show_detailed_exceptions' => false)
      allow(Rails.application).to receive(:env_config).and_return(config)
      allow(User).to receive(:update_counters).and_raise('synthetic counter failure')
      delete "/api/v1/points/#{id + 3}", headers:, env: { 'action_dispatch.show_exceptions' => :all }
      records << { name: 'delete_counter_failure', status: response.status, body: response.body,
                   persisted: Point.exists?(id + 3), own_count: user.reload.points_count }
    end
    RSpec::Mocks.with_temporary_scope do
      config = Rails.application.env_config.merge('action_dispatch.show_exceptions' => :all,
                                                  'action_dispatch.show_detailed_exceptions' => false)
      allow(Rails.application).to receive(:env_config).and_return(config)
      Rails.cache.delete("anomaly_backfill_pending:#{user.id}")
      allow(Points::AnomalyBackfillUserJob).to receive(:perform_later).and_raise('synthetic producer failure')
      post '/api/v1/points/reapply_anomaly_filter', headers: headers
      records << { name: 'anomaly_producer_failure', status: response.status, body: response.body,
                   pending: Rails.cache.read("anomaly_backfill_pending:#{user.id}") }
    end
    RSpec::Mocks.with_temporary_scope do
      config = Rails.application.env_config.merge('action_dispatch.show_exceptions' => :all,
                                                  'action_dispatch.show_detailed_exceptions' => false)
      allow(Rails.application).to receive(:env_config).and_return(config)
      allow(Points::Move).to receive(:call).and_raise('synthetic position write failure')
      patch "/api/v1/points/#{id + 4}/position",
            params: { point: { latitude: '54', longitude: '17', revision: 0 },
                      history_scope: { start_at: '1', end_at: '2147483647' } }, headers: headers
      records << { name: 'position_write_failure', status: response.status, body: response.body,
                   position: Point.find(id + 4).lonlat.as_text }
    end
    path = Rails.root.join('app-phoenix/test/fixtures/a12f2e/closure.json')
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(records)}\n")
  end

  def capture_source_areas
    ActionController::Base.allow_forgery_protection = true
    target = dir.dirname.join('a12f3a-w10.json')
    relabel_target = dir.dirname.join('a12f3a-w11.json')
    snapshots = []
    recipes = [
      [:post, :create, {}, 200], [:post, :create, { name: '' }, 200],
      [:post, :create, { radius: '0' }, 200], [:post, :create, { latitude: '91' }, 200],
      [:post, :create, { longitude: '-181' }, 200], [:post, :nested, {}, 200],
      [:patch, :reshape, { radius: '250' }, 200], [:put, :reshape, { radius: '250' }, 200],
      [:patch, :rename, { name: 'Renamed' }, 200], [:put, :unchanged, {}, 200],
      [:patch, :invalid, { radius: '-5' }, 200], [:patch, :foreign, {}, 404],
      [:put, :missing, {}, 404], [:post, :guest, {}, 302], [:post, :html, {}, 406],
      [:post, :override, { _method: 'put', radius: '250' }, 200]
    ]
    recipes.each_with_index do |(method, kind, changes, expected), index|
      user = reader(95_800 + index * 2)
      foreign = reader(95_801 + index * 2)
      id = 958_000 + index * 10
      unless method == :post && kind != :override
        Area.insert!({ id:, user_id: kind == :foreign ? foreign.id : user.id, name: 'Synthetic area',
                       latitude: 51.3397, longitude: 12.3734, radius: 200, created_at: now, updated_at: now })
      end
      ActiveRecord::Base.connection.execute("SELECT setval(pg_get_serial_sequence('areas', 'id'), #{id + 1}, false)")
      path = if method == :post && kind != :override
               '/areas'
             else
               "/areas/#{kind == :missing ? id + 9 : id}"
             end
      params = { name: 'Synthetic area', latitude: '51.3397', longitude: '12.3734', radius: '200' }.merge(changes)
      params = { area: params } if kind == :nested
      accept = kind == :html ? 'text/html' : 'text/vnd.turbo-stream.html'
      reset!
      sign_in user unless kind == :guest
      get(kind == :guest ? '/users/sign_in' : '/tags/new')
      token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      before = Area.where(user_id: [user.id, foreign.id]).order(:id).map(&:attributes)
      commands = []
      clear_enqueued_jobs
      RSpec::Mocks.with_temporary_scope do
        allow(JobCommands).to receive(:produce).and_wrap_original do |original, type, payload, **options|
          commands << { type:, payload:, **options }
          original.call(type, payload, **options)
        end
        public_send(method, path, params:, headers: { 'Accept' => accept, 'X-CSRF-Token' => token })
      end
      expect(response.status).to eq(expected), kind.to_s
      after = Area.where(user_id: [user.id, foreign.id]).order(:id).map(&:attributes)
      changed = before != after
      invalid_radius = ['0', '-5'].include?(changes[:radius])
      invalid_coordinate = changes[:latitude] == '91' || changes[:longitude] == '-181'
      expected_change = %i[create reshape rename html override].include?(kind) && changes[:name] != '' &&
                        !invalid_radius && !invalid_coordinate
      expect(changed).to eq(expected_change), kind.to_s
      expect(commands.map do
        _1[:type]
      end).to eq(%i[create reshape html
                    override].include?(kind) && expected_change ? ['areas.relabel_visits'] : []), kind.to_s
      snapshots << {
        method: method.to_s.upcase, path:, params:, accept:, kind:, status: response.status,
        body: FixtureRecording.normalize(response.body), media_type: response.media_type, location: response.location,
        vary: response.headers['Vary'], cookie: response.headers['Set-Cookie'].present?, flash: flash.to_hash,
        before:, after:, commands:,
        jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args], queue: _1[:queue] } }
      }
    end
    bytes = "#{Oj.dump(snapshots.as_json, mode: :strict, float_precision: 0, indent: 2)}\n"
    FixtureRecording.source_verify(target, bytes)
    FixtureRecording.source_verify(relabel_target, bytes)
  end

  def generate!
    cases.each_with_index { |name, index| capture(name, index) }
  end

  it 'writes point counters filters and dependent scheduling' do
    generate!
    capture_api_closure!
    capture_source_areas
  end
end
