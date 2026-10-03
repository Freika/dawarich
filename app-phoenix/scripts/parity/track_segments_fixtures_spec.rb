# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: track segment frames', type: :request do
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

  before { FileUtils.mkdir_p(dir) }

  def reader(id, unit: 'km', modes: nil)
    create(:user, id:, email: "a6s3-#{id}@example.invalid", theme: 'light', plan: :pro,
                  changelog_consent: :declined, created_at: now, updated_at: now).tap do |user|
      maps = { 'distance_unit' => unit }
      settings = user.settings.merge('onboarding_completed' => true, 'timezone' => 'UTC', 'maps' => maps)
      settings['enabled_transportation_modes'] = modes if modes
      user.update_columns(api_key: "a6s3-k-#{id}", visits_redetected_at: now - 10.days,
                          settings:)
      user.reload
    end
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
    %w[tracks track_segments].to_h do |table|
      owner = if table == 'track_segments'
                "track_id IN (SELECT id FROM tracks WHERE user_id = #{Integer(user.id)})"
              else
                "user_id = #{Integer(user.id)}"
              end
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{owner} ORDER BY t.id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def track!(user, id)
    from = now - id.seconds
    Track.insert!({ id:, user_id: user.id, start_at: from, end_at: from + 2.days,
                  original_path: 'LINESTRING(12.3 51.3, 12.4 51.4)', distance: 12_345, duration: 172_800,
                   created_at: now, updated_at: now })
    id
  end

  def segment!(track_id, id, mode: :walking, duration: 600, offset: 0, legacy: false, confidence: 0.9, corrected: nil,
               **attrs)
    from = now - 2.days + offset.seconds
    TrackSegment.insert!({ id:, track_id:, transportation_mode: TrackSegment.transportation_modes.fetch(mode.to_s),
                           start_index: id, end_index: id + 1, start_at: legacy ? nil : from,
                           end_at: legacy ? nil : from + duration.to_i.seconds, distance: 1234, duration:,
                           confidence_score: confidence, corrected_at: corrected,
                           created_at: now, updated_at: now }.merge(attrs))
    id
  end

  def capture(name, user, track_id, status: 200, foreign: nil)
    Rails.cache.clear
    reset!
    sign_in user if user
    path = "/tracks/#{track_id}/segments"
    frame = "track-#{track_id}-segments"
    get path, headers: { 'Accept' => accept, 'Turbo-Frame' => frame }
    expect(response.status).to eq(status)
    expect(response.media_type).to eq('text/html')
    doc = Nokogiri::HTML5.fragment(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    if status == 200
      expect(doc.at_css("turbo-frame##{frame}")).to be_present
      segments = TrackSegment.where(track_id:).order(:start_at, :start_index)
      if segments.empty?
        expect(doc.text).to include('No segments for this track yet')
      else
        segments.each do |segment|
          row = doc.at_css("turbo-frame#segment-row-#{segment.id}")
          expect(row).to be_present
          expect(row.at_css('form')['action']).to eq("/tracks/#{track_id}/segments/#{segment.id}")
          expect(row.at_css('input[name="_method"]')['value']).to eq('patch')
          expect(row.at_css('select')['name']).to eq('track_segment[transportation_mode]')
        end
      end
    elsif status == 302
      expect(response.headers['Location']).to include('/users/sign_in')
    end
    state = { 'kind' => 'segments', 'path' => path, 'accept' => accept, 'turbo_frame' => frame,
              'now' => now.iso8601, 'status' => response.status, 'title' => doc.at_css('title')&.text,
              'content_type' => response.media_type,
              'vary' => response.headers['Vary'], 'location' => response.headers['Location'],
              'self_hosted' => DawarichSettings.self_hosted?, 'env' => { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
              'session' => { 'user_return_to' => session[:user_return_to], 'alert' => flash[:alert] },
              'user' => user && user_row(user), 'rows' => user ? rows(user) : {},
              'foreign' => foreign && { 'user' => user_row(foreign), 'rows' => rows(foreign) } }
    File.write(dir.join("#{name}.html"), status == 200 ? doc.to_html : '')
    File.write(dir.join("#{name}.json"), "#{Oj.dump(state, mode: :strict, float_precision: 0, indent: 2)}\n")
    sign_out user if user
    doc
  end

  def raw_cases!(owner)
    track!(owner, 83_201)
    [nil, 0, 3599, 90_061].each_with_index do |duration, i|
      segment!(83_201, 832_101 + i, legacy: true, duration:)
    end
    raw = capture('segments_legacy_durations', owner, 83_201)
    [nil, '0 min', '59 min', '25h 1m'].each_with_index do |label, i|
      row = raw.at_css("#segment-row-#{832_101 + i}")
      expect(row.text).to include(label || '-')
    end
    expect(raw.css('.segment-legs')).to be_empty
    track!(owner, 83_202)
    segment!(83_202, 832_201, mode: :stationary)
    stationary = capture('segments_stationary', owner, 83_202)
    expect(stationary.css('.segment-legs')).to be_empty
    track!(owner, 83_203)
    segment!(83_203, 832_301, duration: 90_061)
    long = capture('segments_long_leg', owner, 83_203)
    expect(long.at_css('.segment-legs').text).to include('1d 1h')
    expect(long.at_css('#segment-row-832301').text).to include('25h 1m')
  end

  def leg_cases!(owner)
    track!(owner, 83_204)
    segment!(83_204, 832_401)
    ordinary = capture('segments_ordinary', owner, 83_204)
    expect(ordinary.at_css('.segment-legs').text).to include('Walking', '10m')
    track!(owner, 83_205)
    segment!(83_205, 832_501, duration: 120)
    short = capture('segments_isolated_short', owner, 83_205)
    expect(short.at_css('.segment-legs').text).to include('Walking', '2m')
    track!(owner, 83_206)
    segment!(83_206, 832_601, duration: 100)
    segment!(83_206, 832_602, mode: :driving, duration: 120, offset: 110)
    transfer = capture('segments_transfer', owner, 83_206)
    expect(transfer.at_css('.segment-legs').text).to include('transfer')
    track!(owner, 83_207)
    segment!(83_207, 832_701, confidence: 0.59)
    segment!(83_207, 832_702, mode: :unknown, offset: 600)
    uncertain = capture('segments_uncertain', owner, 83_207)
    expect(uncertain.css('.segment-legs select').map do |node|
      node.at_css('option[selected]')['value']
    end).to eq(%w[unknown unknown])
    track!(owner, 83_208)
    segment!(83_208, 832_801, duration: 100, confidence: 0.2, corrected: now - 90.seconds)
    segment!(83_208, 832_802, duration: 120, offset: 100, corrected: now - 89.seconds)
    corrected = capture('segments_corrected', owner, 83_208)
    expect(corrected.css('.segment-legs .segment-leg').size).to eq(2)
    expect(corrected.at_css('button[name="reset"]')['value']).to eq('true')
    expect(corrected.at_css('#segment-row-832801').text).not_to include('20%')
    expect(corrected.at_css('#segment-row-832801 [title*="ago"]')['title']).to eq('Edited 2 minutes ago')
    expect(corrected.at_css('#segment-row-832802 [title*="ago"]')['title']).to eq('Edited 1 minute ago')
    [239, 240].each_with_index do |gap, i|
      id = 83_209 + i
      track!(owner, id)
      segment!(id, 832_901 + i * 10)
      segment!(id, 832_902 + i * 10, offset: 600 + gap)
      doc = capture("segments_gap_#{gap}", owner, id)
      expect(doc.css('.segment-stop').size).to eq(i)
    end
    track!(owner, 83_211)
    segment!(83_211, 832_111, duration: 0, corrected: now)
    zero = capture('segments_zero_ribbon', owner, 83_211)
    expect(zero.css('.segment-ribbon i')).to be_empty
  end

  def option_cases!
    owner = reader(8322, unit: 'mi', modes: %w[cycling walking])
    track!(owner, 83_212)
    segment!(83_212, 832_121, mode: :train)
    disabled = capture('segments_disabled_mi', owner, 83_212)
    expect(disabled.at_css('#segment-mode-select-832121')).to be_nil
    select = disabled.at_css('[data-testid="segment-mode-select-832121"]')
    expect(select.css('option').map { |node| node['value'] }).to eq(%w[train cycling walking])
    expect(disabled.at_css('#segment-row-832121').text).to include('0.77 mi')
    owner.update_columns(settings: owner.settings.merge('enabled_transportation_modes' => %w[train cycling walking]))
    enabled = capture('segments_enabled', owner.reload, 83_212)
    expect(enabled.at_css('[data-testid="segment-mode-select-832121"]').css('option').map do |node|
      node['value']
    end).to eq(%w[train cycling walking])
  end

  def generate!
    travel_to now do
      owner = reader(8321)
      foreign = reader(8329)
      track!(owner, 83_200)
      capture('segments_empty', owner, 83_200)
      raw_cases!(owner)
      leg_cases!(owner)
      option_cases!
      track!(foreign, 83_299)
      segment!(83_299, 832_991)
      capture('segments_foreign', owner, 83_299, status: 404, foreign:)
      capture('segments_guest', nil, 83_204, status: 302)
    end
  end

  it 'writes raw and condensed segment frames' do
    generate!
  end
end
