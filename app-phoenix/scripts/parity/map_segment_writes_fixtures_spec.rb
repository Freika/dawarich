# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: map segment writes', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_writes/segments') }
  let(:now) { Time.utc(2026, 10, 3, 10) }
  let(:turbo) { 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml' }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    travel_to(now) { example.run }
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    FileUtils.mkdir_p(dir)
    allow(ExceptionReporter).to receive(:call)
  end

  def reader(id)
    create(:user, id:, email: "a6s4-segment-#{id}@example.invalid", theme: 'light', plan: :pro,
                  changelog_consent: :declined, created_at: now, updated_at: now).tap do |user|
      user.update_columns(api_key: "a6s4-synthetic-#{id}", visits_redetected_at: now - 10.days,
                          settings: user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC',
                                                        'enabled_transportation_modes' =>
                                                        %w[walking cycling driving bus]))
      user.reload
    end
  end

  def track!(user, id, mode: 'cycling')
    Track.insert!({ id:, user_id: user.id, tracker_id: "synthetic-#{id}",
                    start_at: now - 1.hour, end_at: now - 1.hour + 595,
                    original_path: 'LINESTRING(12.3 51.3, 12.4 51.4)', distance: 1000, duration: 595,
                    avg_speed: 6, dominant_mode: Track.dominant_modes.fetch(mode),
                    created_at: now - 1.day, updated_at: now - 1.day })
  end

  def segment!(track_id, id, from: now - 1.hour, to: now - 1.hour + 595, mode: 'cycling', **attrs)
    TrackSegment.insert!({ id:, track_id:, transportation_mode: TrackSegment.transportation_modes.fetch(mode),
                           start_index: nil, end_index: nil, start_at: from, end_at: to,
                           distance: 1000, duration: (to - from).to_i, avg_speed: 6, confidence: 1,
                           confidence_score: 0.7, corrected_at: now - 1.day, source: 'user',
                           created_at: now - 1.day, updated_at: now - 1.day }.merge(attrs))
  end

  def trace!(user, id, track_id, short_chains: false)
    trace = TransportationTraceGenerator.trip(legs: [{ mode: :walking, duration_s: 600, dt_s: 5 }],
                                              start_time: now - 1.hour, seed: 42)
    points = short_chains ? trace[:points].first(8) : trace[:points]
    Point.insert_all(points.map.with_index do |p, index|
      timestamp = short_chains ? (now - 1.hour).to_i + (index / 4) * 600 + (index % 4) * 5 : p[:timestamp]
      { id: id + index, user_id: user.id, track_id:, timestamp:,
        lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})", accuracy: p[:accuracy], velocity: p[:velocity].to_s,
        created_at: now - 1.day, updated_at: now - 1.day }
    end)
  end

  def graph(user, foreign)
    ids = [user.id, foreign.id].join(',')
    %w[tracks track_segments points].to_h do |table|
      scope = if table == 'track_segments'
                "track_id IN (SELECT id FROM tracks WHERE user_id IN (#{ids}))"
              else
                "user_id IN (#{ids})"
              end
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{scope} ORDER BY id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { JSON.parse(_1) }]
    end
  end

  def cases
    %w[override_condensed override_raw override_unchanged override_tied disabled reset_changed reset_unchanged
       reset_preserved reset_empty reset_failure html_referer html_root html_disabled html_reset_failure
       override_post reset_post foreign_track wrong_nested missing_track missing_segment guest
       accept_turbo_only accept_html_first accept_turbo_q accept_html_q accept_wildcard]
  end

  def seed(user, foreign, id, name)
    mode = %w[override_unchanged reset_unchanged].include?(name) ? 'walking' : 'cycling'
    track!(user, id, mode:)
    track!(foreign, id + 1)
    track!(user, id + 2)
    segment!(id, id * 10, mode: name == 'override_unchanged' ? 'walking' : 'cycling')
    segment!(id + 1, id * 10 + 1)
    segment!(id + 2, id * 10 + 2)
    case name
    when 'override_raw'
      TrackSegment.where(id: id * 10).update_all(start_at: nil, end_at: nil, start_index: 0, end_index: 119)
    when 'override_tied'
      segment!(id, id * 10 + 3, mode: 'driving', from: now - 1.hour + 600, to: now - 1.hour + 1195)
    when 'reset_preserved'
      segment!(id, id * 10 + 3, mode: 'bus', from: now - 1.hour + 100, to: now - 1.hour + 200)
      segment!(id, id * 10 + 4, mode: 'driving', from: now - 1.hour + 300, to: now - 1.hour + 400,
               corrected_at: nil, source: EnhancedImport::Translator::SEGMENT_SOURCE_LABELS.first)
    end
    trace!(user, id * 100, id, short_chains: name == 'reset_empty') if name.include?('reset')
    Track.where(id:).update_all(end_at: now - 1.hour + 615, duration: 615) if name == 'reset_empty'
    sql = "SELECT setval(pg_get_serial_sequence('track_segments', 'id'), #{id * 10 + 5}, false)"
    ActiveRecord::Base.connection.execute(sql)
  end

  def accept_for(name)
    { 'accept_turbo_only' => 'text/vnd.turbo-stream.html',
      'accept_html_first' => 'text/html, text/vnd.turbo-stream.html',
      'accept_turbo_q' => 'text/html;q=0.5, text/vnd.turbo-stream.html;q=1',
      'accept_html_q' => 'text/vnd.turbo-stream.html;q=0.5, text/html;q=1',
      'accept_wildcard' => '*/*' }.fetch(name, name.start_with?('html_') ? 'text/html' : turbo)
  end

  def capture(name, index)
    user = reader(9300 + index * 2)
    foreign = reader(9301 + index * 2)
    id = 930_000 + index * 10
    seed(user, foreign, id, name)
    Rails.cache.clear
    reset!
    sign_in user unless name == 'guest'
    get(name == 'guest' ? '/users/sign_in' : '/tags/new')
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    before = graph(user, foreign)
    before_session = { 'flash' => session['flash'], 'csrf_present' => session[:_csrf_token].present? }
    @epochs = []
    @broadcasts = []
    allow(Tracks::TileEpoch).to receive(:bump_range) { |*args| @epochs << args }
    allow(TracksChannel).to receive(:broadcast_to) { |actor, data|
      @broadcasts << { 'user_id' => actor.id, 'data' => data.as_json }
    }
    method = name.end_with?('_post') ? :post : :patch
    reset = name.include?('reset')
    params = if reset
               { reset: 'true' }
             else
               { track_segment: { transportation_mode: name.include?('disabled') ? 'flying' : 'walking' } }
             end
    params[:_method] = 'patch' if method == :post
    track_id = if name == 'foreign_track'
                 id + 1
               else
                 name == 'missing_track' ? id + 9 : id
               end
    segment_id = case name
                 when 'foreign_track' then id * 10 + 1
                 when 'wrong_nested' then id * 10 + 2
                 when 'missing_segment' then id * 10 + 9
                 else id * 10
                 end
    path = "/tracks/#{track_id}/segments/#{segment_id}"
    accept = accept_for(name)
    headers = { 'Accept' => accept, 'X-CSRF-Token' => token }
    headers['Referer'] = 'http://www.example.com/points?order_by=asc' if name == 'html_referer'
    clear_enqueued_jobs
    RSpec::Mocks.with_temporary_scope do
      if name.include?('reset_failure')
        allow(TransportationModes::FeatureExtractor).to receive(:call).and_raise(StandardError,
                                                                                 'synthetic detector failure')
      end
      public_send(method, path, params:, headers:)
    end
    status = expected_status(name)
    expect(response.status).to eq(status), name
    after = graph(user, foreign)
    assert_change(name, user, id, before, after)
    doc = Nokogiri::HTML5.fragment(response.body)
    doc.css('input[name="authenticity_token"]').each { _1['value'] = 'CSRF' }
    streams = doc.css('turbo-stream').map { [_1['action'], _1['target']] }
    html = name.start_with?('html_') || %w[accept_html_first accept_html_q].include?(name)
    if status == 200
      expected = reset ? [['replace', "track-#{id}-segments"]] : [['replace', "segment-row-#{id * 10}"]]
      expected << ['replace', "track-#{id}-legs"] unless reset || name == 'override_raw'
      expected += [['update', "track-info-mode-#{id}"], %w[append flash-messages]]
      expect(streams).to eq(expected), name
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
    elsif status == 422
      expect(streams).to eq([%w[append flash-messages]]), name
    elsif html
      expected = name == 'html_referer' ? 'http://www.example.com/points?order_by=asc' : 'http://www.example.com/'
      expect(response.location).to eq(expected), name
    end
    state = { 'now' => now.iso8601(6), 'request' => { 'method' => method.to_s.upcase, 'path' => path,
                                                   'params' => params.deep_stringify_keys, 'accept' => accept,
                                                   'referer' => headers['Referer'] },
              'user' => user.attributes.slice('id', 'email', 'theme', 'settings', 'api_key', 'plan', 'status'),
              'before' => before, 'after' => after, 'status' => response.status, 'content_type' => response.media_type,
              'vary' => response.headers['Vary'], 'location' => response.location, 'flash' => flash.to_hash,
              'session_before' => before_session,
              'session_after' => { 'flash' => session['flash'], 'csrf_present' => session[:_csrf_token].present? },
              'set_cookie' => response.headers['Set-Cookie'].present?, 'streams' => streams,
              'epochs' => @epochs, 'broadcasts' => @broadcasts,
              'association_order' => Track.find(id).track_segments.pluck(:id),
              'jobs' => enqueued_jobs.map { { 'job' => _1[:job].name, 'args' => _1[:args] } } }
    File.write(dir.join("#{name}.html"), [200, 422].include?(status) ? doc.to_html : '')
    File.write(dir.join("#{name}.json"), "#{Oj.dump(state, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  def expected_status(name)
    return 404 if %w[foreign_track wrong_nested missing_track missing_segment].include?(name)
    return 302 if name.start_with?('html_') || %w[guest accept_html_first accept_html_q].include?(name)
    return 422 if name.include?('disabled') || name.include?('reset_failure')

    200
  end

  def assert_change(name, user, id, before, after)
    if name.include?('disabled') || name.include?('failure') || %w[foreign_track wrong_nested missing_track
                                                                   missing_segment guest].include?(name)
      expect(after).to eq(before), name
      expect(@epochs).to be_empty, name
      expect(@broadcasts).to be_empty, name
      return
    end
    track = user.tracks.find(id)
    if name == 'reset_empty'
      expect(track.track_segments).to be_empty
      expect(track.dominant_mode).to eq('cycling')
      expect(track.updated_at).to eq(now - 1.day)
      expect(@epochs).to be_empty
      expect(@broadcasts).to be_empty
      return
    end
    expect(@epochs).to eq([[user.id, track.start_at.to_i, track.end_at.to_i]]), name
    expect(@broadcasts.map { _1['data']['action'] }).to eq(['updated']), name
    unchanged = %w[override_unchanged reset_unchanged].include?(name)
    expect(track.updated_at).to eq(unchanged ? now - 1.day : now), name
    expect(track.lock_version).to eq(unchanged ? 0 : 1), name
    if name.include?('reset')
      expect(track.track_segments.where(id: id * 10)).to be_empty, name
      fresh = track.track_segments.where('id >= ?', id * 10 + 5)
      expect(fresh).not_to be_empty, name
      fresh.each { expect([_1.created_at, _1.updated_at]).to eq([now, now]), name }
      expect(track.track_segments.where(id: [id * 10 + 3, id * 10 + 4]).count).to eq(2) if name == 'reset_preserved'
    else
      segment = track.track_segments.find(id * 10)
      expect(segment.transportation_mode).to eq('walking'), name
      expect([segment.corrected_at, segment.updated_at, segment.confidence, segment.confidence_score, segment.source])
        .to eq([now, now, 'high', 1.0, 'user']), name
      expect(track.dominant_mode).to eq(name == 'override_tied' ? 'driving' : 'walking'), name
    end
  end

  def generate!
    cases.each_with_index { |name, index| capture(name, index) }
  end

  it 'writes segment override reset failure and stream targets' do
    generate!
  end
end
