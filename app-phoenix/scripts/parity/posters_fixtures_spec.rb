# frozen_string_literal: true

require 'rails_helper'
require_relative 'poster_fixture_support'

RSpec.describe 'Phoenix fixtures: poster persistence and generation', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include PosterFixtureSupport

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/posters') }
  let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }

  before do
    FileUtils.mkdir_p(dir)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    command = [RbConfig.ruby, Rails.root.join('spec/fixtures/scripts/fake_poster_renderer.rb').to_s]
    allow(Posters::NativeRenderer).to receive(:new).and_wrap_original do |original, **args|
      renderer = original.call(**args, command:)
      deleting = @delete_during_render == args[:poster].id
      allow(renderer).to receive(:call).and_wrap_original do |render|
        args[:poster].delete if deleting
        render.call
      end
      renderer
    end
    allow(Dir).to receive(:mktmpdir).and_call_original
    allow(Dir).to receive(:mktmpdir).with('poster_render').and_wrap_original do |_original, &block|
      path = 'tmp/a9fpl-poster-render'
      FileUtils.mkdir_p(path)
      begin
        block.call(path)
      ensure
        FileUtils.rm_rf(path)
      end
    end
  end

  around do |example|
    id = 96_000
    assign_id = ->(record) { record.id ||= (id += 1) }
    Poster.set_callback(:create, :before, assign_id)
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    Poster.skip_callback(:create, :before, assign_id)
    ActionController::Base.allow_forgery_protection = false
  end

  def poster_requests(user, foreign, locale)
    user.update_columns(settings: user.settings.merge('locale' => locale))
    attributes = poster_settings.merge('name' => 'Leipzig', 'title' => 'Weekend', 'route_width' => '250',
                                       'route_fill' => '1', 'route_opacity' => '40',
                                       'layout' => 'ignored', 'font' => 'ignored', 'paper' => 'ignored')
    capture_poster_request("create_whitelist_#{locale}", user, :post, '/posters',
                           params: { poster: attributes }, turbo: true)
    expect(user.posters.last.settings['route_width']).to eq('250')
    %w[blank_name blank_title missing_title].each do |kind|
      params = case kind
               when 'blank_name' then attributes.merge('name' => '')
               when 'blank_title' then attributes.merge('title' => '')
               else attributes.except('title')
               end
      capture_poster_request("create_#{kind}_#{locale}", user, :post, '/posters', params: { poster: params })
    end
    [false, true].each do |turbo|
      capture_poster_request("create_error_#{turbo}_#{locale}", user, :post, '/posters', turbo:)
      poster = fixture_poster(user, turbo ? 96_501 : 96_502)
      capture_poster_request("delete_#{turbo}_#{locale}", user, :delete, "/posters/#{poster.id}", turbo:)
    end
    poster = fixture_poster(foreign, locale == 'en' ? 96_601 : 96_602)
    capture_poster_request("delete_foreign_#{locale}", user, :delete, "/posters/#{poster.id}", turbo: true)
  end

  def poster_geometry_cases(user)
    Point.where(user:).delete_all
    [0, 60, 3660, 7261, 7321].each_with_index { |offset, i| poster_point(user, 97_301 + i, -8000 + offset) }
    poster_point(user, 97_310, nil)
    poster_point(user, 97_311, -10, 'POINT(12.3811 51.3437)', anomaly: true)
    capture_poster_generation('points_gap_boundaries', fixture_poster(user, 96_701))
    Point.where(user:).delete_all
    capture_poster_generation('absent_points', fixture_poster(user, 96_702))
    poster_point(user, 97_312, -300, 'POINT(12.49 41.90)')
    poster_point(user, 97_313, -200, 'POINT(12.50 41.91)')
    capture_poster_generation('outside_frame', fixture_poster(user, 96_703))
    Point.where(user:).delete_all
    poster_point(user, 97_314, -300, 'POINT(-179 -18)')
    poster_point(user, 97_315, -200, 'POINT(-178.9 -18.1)')
    settings = poster_settings.merge('lat' => '-18', 'lon' => '178', 'distance' => '2000000')
    capture_poster_generation('antimeridian', fixture_poster(user, 96_704, settings:))
    Point.where(user:).delete_all
    poster_point(user, 97_316, -300)
    poster_point(user, 97_317, -200)
    [['low', '1', '2', '10'], ['high', '6000000', '400', '900'],
     ['zero', '6000', '0', '-50']].each_with_index do |(label, distance, opacity, width), i|
      settings = poster_settings.merge('distance' => distance, 'route_opacity' => opacity, 'route_width' => width)
      capture_poster_generation("clamps_#{label}", fixture_poster(user, 96_710 + i, settings:))
    end
    Track.insert!({ id: 97_401, user_id: user.id, start_at: now - 2.days, end_at: now - 23.hours,
                    original_path: 'LINESTRING(12.3731 51.3397,12.3811 51.3437)',
                    created_at: now, updated_at: now })
    Track.insert!({ id: 97_402, user_id: user.id, start_at: now - 12.hours, end_at: now - 10.hours,
                    original_path: 'LINESTRING(12.3731 51.3397,12.3901 51.3402)',
                    created_at: now, updated_at: now })
    Track.insert!({ id: 97_403, user_id: user.id, start_at: now + 1.day, end_at: now + 2.days,
                    original_path: 'LINESTRING(12.3901 51.3402,12.3811 51.3437)',
                    created_at: now, updated_at: now })
    settings = poster_settings.merge('source' => 'tracks', 'theme' => '../terracotta')
    capture_poster_generation('overlapping_tracks_theme_basename', fixture_poster(user, 96_720, settings:))
    poster = fixture_poster(user, 96_721)
    @delete_during_render = poster.id
    capture_poster_generation('deletion_during_render', poster)
    @delete_during_render = nil
    capture_poster_generation('already_completed_without_pair', fixture_poster(user, 96_722, status: :completed))
    ['', 'Weekend'].each_with_index do |title, i|
      settings = poster_settings.merge('title' => title)
      capture_poster_generation("render_title_#{i}", fixture_poster(user, 96_730 + i, settings:))
    end
    %w[fetching_data drawing_map drawing_route saving unknown].each_with_index do |phase, i|
      settings = poster_settings.merge('progress_phase' => phase)
      poster = fixture_poster(user, 96_740 + i, status: :processing, settings:)
      write_poster("phase_#{phase}", { 'poster' => poster_row(poster) }, poster_card(poster))
    end
    settings = poster_settings.merge('theme' => 'missing-fixture-theme')
    capture_poster_generation('unknown_theme', fixture_poster(user, 96_750, settings:))
    begin
      Posters::CreateJob.perform_now(96_999)
    rescue ActiveRecord::RecordNotFound => e
      write_poster('missing_job_row', { 'error' => e.class.name })
    end
  end

  it 'writes poster whitelist gallery streams and renderer job contracts' do
    travel_to now do
      user = poster_actor(97_101)
      foreign = poster_actor(97_102)
      %w[en de].each { |locale| poster_requests(user, foreign, locale) }
      poster_geometry_cases(user)
      expect(File.exist?(dir.join('create_whitelist_en.json'))).to be(true)
      %w[en de].each do |locale|
        html = File.read(dir.join("delete_foreign_#{locale}.html"))
        expect(html).not_to match(/_csrf_token:|session_id:|warden\.user\.user\.key:/)
        expect(html).to include('HTTP_X_CSRF_TOKEN: "CSRF"')
      end
    end
  end

  it 'in range null lonlat preserves Rails segment and generation failure behavior' do
    travel_to now do
      user = poster_actor(97_101)
      poster_point(user, 97_201, -300, nil)
      poster_point(user, 97_202, -200)
      poster_point(user, 97_203, -100)
      poster = fixture_poster(user, 97_001)
      data = capture_poster_generation('null_lonlat', poster)
      expect(data['track']['coordinates'].first).to include([nil, nil])
      expect(poster.reload.status).to eq('failed')
      expect(poster.image.attached?).to be(false)
      expect(poster.print_pdf.attached?).to be(false)
      expect(File.exist?(dir.join('null_lonlat.json'))).to be(true)
    end
  end

  it 'keeps rendered poster attachment paths independent of the worktree' do
    allow(self).to receive(:write_poster) { |_name, data, _html| data }
    travel_to now do
      user = poster_actor(97_101)
      poster_point(user, 97_201, -300)
      poster_point(user, 97_202, -200)
      data = capture_poster_generation('points_gap_boundaries', fixture_poster(user, 96_701))
      job = JSON.parse(Base64.strict_decode64(data['attachments'].first['bytes_base64']))
      expect(job.dig('output', 'png')).to eq('tmp/a9fpl-poster-render/poster.png')
      expect(job.dig('output', 'pdf')).to eq('tmp/a9fpl-poster-render/poster.pdf')
    end
  end

  it 'verifies committed poster fixtures without writing by default' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WRITE_POSTER_FIXTURES').and_return(nil)
    expect(File).not_to receive(:write)
    write_poster('missing_job_row', { 'error' => 'ActiveRecord::RecordNotFound' })
    expect do
      write_poster('missing_job_row', { 'error' => 'changed' })
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /missing_job_row.json differs/)
  end

  it 'verifies UTF-8 poster fixtures by bytes' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WRITE_POSTER_FIXTURES').and_return(nil)
    expect(File).not_to receive(:write)
    data = JSON.parse(File.read(dir.join('null_lonlat.json')))
    html = File.read(dir.join('null_lonlat.html'))
    write_poster('null_lonlat', data, html)
  end

  it 'writes poster timestamp generation outcomes in the job default timezone' do
    FileUtils.mkdir_p(dir.join('timestamps'))
    travel_to now do
      Time.use_zone(ENV.fetch('TIME_ZONE', 'Europe/Berlin')) do
        user = poster_actor(97_101)
        cases = {
          'no_offset' => ['2026-10-03T00:00:00', '2026-10-03T00:45:00'],
          'date_only' => %w[2026-10-03 2026-10-04],
          'explicit_offset' => ['2026-10-03T00:00:00+02:00', '2026-10-03T00:45:00+02:00'],
          'dst_spring' => ['2026-03-29T02:15:00', '2026-03-29T03:45:00'],
          'dst_fall' => ['2026-10-25T02:15:00', '2026-10-25T02:45:00'],
          'beyond_2038' => ['2040-10-03T00:00:00', '2040-10-03T00:45:00'],
          'beyond_2038_points' => ['2040-10-03T00:00:00', '2040-10-03T00:45:00'],
          'human_date' => ['Oct 3, 2026 00:00', 'Oct 3, 2026 00:45'],
          'fractional_tracks' => ['2026-10-03T00:00:00.750', '2026-10-03T00:45:00.125'],
          'missing' => [nil, nil],
          'blank' => ['', ''],
          'blank_epoch_points' => ['', ''],
          'blank_tracks' => ['', ''],
          'whitespace' => ['  ', '  ']
        }

        cases.each_with_index do |(label, (first, last)), i|
          Point.where(user:).delete_all
          Track.where(user:).delete_all
          settings = poster_settings.merge('start_at' => first, 'end_at' => last)
          settings = settings.except('start_at', 'end_at') if label == 'missing'

          if %w[beyond_2038 fractional_tracks blank_tracks].include?(label)
            settings['source'] = 'tracks'
            first_time = Time.zone.parse(first) || now - 1.day
            last_time = Time.zone.parse(last) || now
            Track.insert!({ id: 97_451, user_id: user.id, start_at: first_time,
                            end_at: last_time,
                            original_path: 'LINESTRING(12.3731 51.3397,12.3811 51.3437)',
                            created_at: now, updated_at: now })
            if label == 'fractional_tracks'
              Track.insert!({ id: 97_452, user_id: user.id, start_at: first_time - 0.5, end_at: first_time - 0.25,
                              original_path: 'LINESTRING(12.39 51.34,12.38 51.35)', created_at: now, updated_at: now })
            end
          elsif label == 'blank_epoch_points'
            poster_point(user, 97_451, -now.to_i)
            poster_point(user, 97_452, -now.to_i, 'POINT(12.3811 51.3437)')
          elsif %w[missing blank whitespace beyond_2038_points].exclude?(label)
            start_at = Time.zone.parse(first)
            [60, 120].each_with_index { |offset, j| poster_point(user, 97_451 + j, start_at.to_i - now.to_i + offset) }
            [-600, -500].each_with_index do |offset, j|
              poster_point(user, 97_455 + j, start_at.to_i - now.to_i + offset)
            end
          end

          data = capture_poster_generation("timestamps/#{label}", fixture_poster(user, 96_801 + i, settings:))
          expect(data['time_zone']).to eq(ENV.fetch('TIME_ZONE', 'Europe/Berlin'))
          if %w[missing blank whitespace blank_epoch_points blank_tracks beyond_2038_points].include?(label)
            expect(data['after']['status']).to eq(3)
            expect(data['attachments']).to eq([])
          else
            expect(data['after']['status']).to eq(2)
            expect(data['attachments'].map { |attachment| attachment['name'] }).to eq(%w[image print_pdf])
            expect(data['track']['coordinates'].length).to eq(1)
            expect(data['track']['coordinates'].first.length).to eq(2)
          end
        end

        Time.use_zone('America/New_York') do
          Point.where(user:).delete_all
          Track.where(user:).delete_all
          settings = poster_settings.merge('start_at' => '2026-10-03T00:00:00',
                                           'end_at' => '2026-10-03T00:45:00')
          start_at = Time.zone.parse(settings['start_at'])
          [60, 120].each_with_index { |offset, j| poster_point(user, 97_451 + j, start_at.to_i - now.to_i + offset) }
          data = capture_poster_generation('timestamps/configured_zone', fixture_poster(user, 96_850, settings:))
          expect(data['time_zone']).to eq('America/New_York')
          expect(data['after']['status']).to eq(2)
        end
      end
    end
  end
end
