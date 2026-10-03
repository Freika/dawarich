# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the trips pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/trips') }
  let(:now) { Time.utc(2026, 9, 29, 12, 0, 0) }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }
  let(:helper) { ApplicationController.helpers }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before { FileUtils.mkdir_p(dir.join('pages')) }

  def write_json(name, data)
    File.write(dir.join(name), "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  def utc(text) = Time.iso8601(text)

  context 'A8 route videos' do
    let(:now) { Time.utc(2026, 10, 3, 10, 0, 0) }
    let(:a8_recipe) do
      { 'theme' => 'dark', 'format' => 'landscape', 'duration_sec' => '15', 'camera_mode' => 'follow',
        'follow_zoom' => '14', 'track_color' => '#aa33cc', 'track_width' => '4', 'hud_scale' => '1',
        'units' => 'km', 'watermark' => 'true', 'visualization_mode' => 'route', 'fog_opacity' => '0.4',
        'fog_color' => '#ffffff', 'show_marker' => 'true', 'show_route' => 'true', 'source' => 'trip',
        'start_at' => '2026-10-03T08:00:00Z', 'end_at' => '2026-10-03T09:00:00Z' }
    end

    def a8_video_user(id)
      user = create(:user, id:, email: "a8vv-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true },
                          plan: User.plans[:pro], api_key: "a8vv-k-#{id}", theme: 'dark')
      user.reload
    end

    def a8_blob(id, type: 'video/mp4', size: nil)
      bytes = Rails.root.join('spec/fixtures/files/route_video.mp4').binread
      blob = ActiveStorage::Blob.create!(id:, key: "a8vv-synthetic-#{id}", filename: 'synthetic-route.mp4',
                                         content_type: type, byte_size: size || bytes.bytesize,
                                         checksum: Digest::MD5.base64digest(bytes), service_name: 'test',
                                         metadata: { identified: true, analyzed: true }, created_at: now - 1.hour)
      blob.service.upload(blob.key, StringIO.new(bytes), checksum: blob.checksum)
      blob
    end

    def a8_video(user, id, blob: nil, created_at: now - 2.hours, status: :stored)
      video = RouteVideo.create!(id:, user:, name: 'Synthetic route', settings: a8_recipe,
                                 status:, created_at:, updated_at: created_at,
                                 expired_at: status == :expired ? now - 1.hour : nil)
      if blob
        ActiveStorage::Attachment.create!(id:, name: 'file', record: video, blob:, created_at:)
        video.update_columns(updated_at: created_at)
      end
      video.reload
    end

    def a8_video_graph(user)
      video_ids = user.route_videos.order(:id).pluck(:id)
      first_blob = user.id < 8880 ? 886_000 + (user.id - 8860) * 10 : 888_000 + (user.id - 8880) * 10
      blob_ids = ActiveStorage::Blob.where(id: first_blob...first_blob + 10).order(:id).pluck(:id)
      { user: { id: user.id, email: user.email, settings: user.settings, plan: User.plans[user.plan],
                theme: user.theme, active_until: user.active_until.utc.iso8601(6) },
        route_videos: RouteVideo.where(id: video_ids).order(:id).map { a8_video_attributes(_1) },
        active_storage_attachments: ActiveStorage::Attachment.where(blob_id: blob_ids).order(:id).map do
          a8_video_attributes(_1)
        end,
        active_storage_blobs: ActiveStorage::Blob.where(id: blob_ids).order(:id).map { a8_video_attributes(_1) } }
    end

    def a8_video_attributes(row)
      attrs = row.attributes.transform_values { _1.respond_to?(:utc) ? _1.utc.iso8601(6) : _1 }
      attrs['status'] = RouteVideo.statuses[row.status] if row.is_a?(RouteVideo)
      attrs
    end

    def a8_video_card(video)
      ApplicationController.render(partial: 'route_videos/route_video', locals: { route_video: video })
    end

    def a8_video_record(name, user, before, request, body: response.body, status: response.status)
      target = Rails.root.join('app-phoenix/test/fixtures/a8vv/videos')
      FileUtils.mkdir_p(target)
      body = body.gsub(%r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/]+/}, '\1BLOB_SIGNED_ID/')
      File.write(target.join("#{name}.html"), body)
      data = { now: now.iso8601, request:, before:, after: a8_video_graph(user), status:,
               content_type: request[:method] ? response.media_type : 'text/html',
               location: request[:method] ? response.location : nil,
               flash: request[:method] ? flash.to_hash : {},
               headers: if request[:method]
                          response.headers.slice('Content-Type', 'Location', 'Vary', 'Cache-Control',
                                                 'X-Frame-Options', 'Referrer-Policy', 'X-Content-Type-Options')
                        else
                          {}
                        end,
               jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args], queue: _1[:queue] } } }
      File.write(target.join("#{name}.json"),
                 "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n")
    end

    def a8_video_request(user, method, path, params: {}, accept: 'text/vnd.turbo-stream.html')
      reset!
      sign_in user
      get '/settings/visits'
      token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
      clear_enqueued_jobs
      public_send(method, path, params:, headers: { 'X-CSRF-Token' => token, 'Accept' => accept })
    end

    it 'writes A8 video responses and effects' do
      travel_to now do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(10)
        allow(ExceptionReporter).to receive(:call)
        cases = %w[all_recipe_keys untitled unknown_recipe unicode_recipe_65 exact_ceiling wrong_mime
                   over_ceiling invalid_signature pre_attach_error post_commit_cap_error cap_one cap_zero]
        cases.each_with_index do |name, index|
          user = a8_video_user(8860 + index)
          id = 886_000 + index * 10
          allow(DawarichSettings).to receive(:video_max_per_user).and_return(name == 'cap_one' ? 1 : 0)
          mime = name == 'wrong_mime' ? 'text/plain' : 'video/mp4'
          size = { 'exact_ceiling' => 250 * 1024 * 1024, 'over_ceiling' => 250 * 1024 * 1024 + 1 }[name]
          blob = a8_blob(id, type: mime, size:)
          old = nil
          if %w[cap_one cap_zero post_commit_cap_error].include?(name)
            old = a8_video(user, id + 1, blob: a8_blob(id + 1))
            allow(DawarichSettings).to receive(:video_max_per_user).and_return(name == 'cap_zero' ? 0 : 1)
          end
          %w[route_videos active_storage_attachments].each do |table|
            ActiveRecord::Base.connection.execute(
              "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 2}, false)"
            )
          end
          recipe = a8_recipe.dup
          recipe['unknown'] = 'discard' if name == 'unknown_recipe'
          unicode = "#{'a' * 61}é👩‍💻end"
          recipe['source'] = unicode if name == 'unicode_recipe_65'
          params = { route_video: { name: name == 'untitled' ? '' : 'Saved route', file: blob.signed_id,
                                   settings: recipe } }
          params[:route_video][:file] = 'invalid-signed-id' if name == 'invalid_signature'
          before = a8_video_graph(user)
          RSpec::Mocks.with_temporary_scope do
            if name == 'pre_attach_error'
              allow_any_instance_of(RouteVideo).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(RouteVideo.new))
            elsif name == 'post_commit_cap_error'
              allow_any_instance_of(RouteVideo).to receive(:update!).and_raise('synthetic expiry status failure')
            end
            a8_video_request(user, :post, '/route_videos', params:)
          end
          rejected = %w[wrong_mime over_ceiling invalid_signature pre_attach_error post_commit_cap_error].include?(name)
          expect(response.status).to eq(rejected ? 422 : 200), name
          saved = user.route_videos.find_by(id: id + 2)
          if %w[wrong_mime over_ceiling invalid_signature pre_attach_error].include?(name)
            expect(saved).to be_nil, name
            expect(blob.attachments).to be_empty
            if name == 'invalid_signature'
              expect(enqueued_jobs).to be_empty
            else
              expect(enqueued_jobs.select { _1[:job] == ActiveStorage::PurgeJob }.size).to eq(1)
            end
          else
            expect(saved).to be_present, name
            expect(saved.file.blob.id).to eq(blob.id)
            expect(saved.name).to eq(name == 'untitled' ? I18n.t('controllers.route_videos.untitled') : 'Saved route')
            wanted = a8_recipe.merge(name == 'unicode_recipe_65' ? { 'source' => "#{'a' * 61}é👩" } : {})
            expect(saved.settings).to eq(wanted), name
            if old
              expect(old.reload.status).to eq(name == 'cap_one' ? 'expired' : 'stored')
              expect(old.file.attached?).to eq(name == 'cap_zero')
              expect(old.updated_at).to eq(name == 'cap_zero' ? now - 2.hours : now)
              expect(old.expired_at).to eq(name == 'cap_one' ? now : nil)
            end
            streams = Nokogiri::HTML5.fragment(response.body).css('turbo-stream').map { [_1['action'], _1['target']] }
            wanted_streams = if name == 'post_commit_cap_error'
                               [%w[append flash-messages]]
                             else
                               [%w[prepend route-video-gallery-list],
                                *(name == 'cap_one' ? [['replace', "route_video_#{old.id}"]] : []),
                                %w[append flash-messages]]
                             end
            expect(streams).to eq(wanted_streams)
          end
          reference = name == 'invalid_signature' ? 'INVALID_SIGNED_ID' : 'BLOB_SIGNED_ID'
          request = { method: 'POST', path: '/route_videos', accept: 'text/vnd.turbo-stream.html',
                      params: params.deep_merge(route_video: { file: reference }),
                      blob_id: blob.id,
                      fault: %w[pre_attach_error post_commit_cap_error].include?(name) ? name : nil }
          a8_video_record(name, user, before, request)
        end

        %w[playable_card expired_card stored_without_file destroy_html destroy_stream shared_blob
           aged_boundary].each_with_index do |name, index|
          user = a8_video_user(8880 + index)
          id = 888_000 + index * 10
          blob = a8_blob(id) unless name == 'stored_without_file'
          video = a8_video(user, id, blob:, status: name == 'expired_card' ? :expired : :stored)
          before = a8_video_graph(user)
          clear_enqueued_jobs
          if name.start_with?('destroy_')
            accept = name == 'destroy_html' ? 'text/html' : 'text/vnd.turbo-stream.html'
            a8_video_request(user, :delete, "/route_videos/#{id}", accept:)
            expect(response.status).to eq(name == 'destroy_html' ? 303 : 200)
            expect(RouteVideo.exists?(id)).to be(false)
            expect(ActiveStorage::Attachment.where(record_type: 'RouteVideo', record_id: id)).to be_empty
            expect(enqueued_jobs.select { _1[:job] == ActiveStorage::PurgeJob }.size).to eq(1)
            if name == 'destroy_html'
              expect(response).to redirect_to('/map/v2')
            else
              expect(response.body).to eq(
                "<turbo-stream action=\"remove\" target=\"route_video_#{id}\"></turbo-stream>"
              )
            end
            a8_video_record(name, user, before, { method: 'DELETE', path: "/route_videos/#{id}", accept: })
          elsif name == 'shared_blob'
            second = a8_video(user, id + 1, blob:)
            before = a8_video_graph(user)
            video.expire!
            expect(video.reload.status).to eq('expired')
            expect(video.file.attached?).to be(false)
            expect(video.settings).to eq(a8_recipe)
            expect(video.updated_at).to eq(now)
            expect(video.expired_at).to eq(now)
            purge_args = enqueued_jobs.select { _1[:job] == ActiveStorage::PurgeJob }.map { _1[:args] }
            expect(purge_args).to eq([[{ '_aj_globalid' => "gid://dawarich/ActiveStorage::Blob/#{blob.id}" }]])
            queued = enqueued_jobs.map { { job: _1[:job].name, args: _1[:args] } }
            perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
            expect(second.reload.file.attached?).to be(true)
            expect(ActiveStorage::Blob.exists?(blob.id)).to be(true)
            expect(blob.service.exist?(blob.key)).to be(true)
            a8_video_record(name, user, before, { operation: 'expire_and_purge', video_id: id, queued: },
                            body: a8_video_card(video), status: 200)
          elsif name == 'aged_boundary'
            video.update_columns(created_at: now - 30.days - 1.second)
            boundary = a8_video(user, id + 1, blob: a8_blob(id + 1), created_at: now - 30.days)
            allow(DawarichSettings).to receive(:video_retention_days).and_return(30)
            allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
            before = a8_video_graph(user)
            RouteVideos::PurgeJob.perform_now
            expect(video.reload.status).to eq('expired')
            expect(video.file.attached?).to be(false)
            expect(boundary.reload.status).to eq('stored')
            expect(boundary.file.attached?).to be(true)
            a8_video_record(name, user, before, { operation: 'retention', days: 30, cap: 0 },
                            body: a8_video_card(video), status: 200)
          else
            body = a8_video_card(video)
            if name == 'playable_card'
              expect(Nokogiri::HTML5.fragment(body).at_css('video')['controls']).not_to be_nil
              expect(body).to include('disposition=attachment')
            else
              expect(Nokogiri::HTML5.fragment(body).css('video')).to be_empty
              expect(body).to include('video-studio#restoreSettings')
            end
            a8_video_record(name, user, before, { operation: 'card', video_id: id }, body:, status: 200)
          end
        end
      end
    end

    it 'writes A8 attachment identification boundaries' do
      travel_to now do
        allow(DawarichSettings).to receive(:video_max_per_user).and_return(0)
        %w[unidentified preidentified shared_preidentified].each_with_index do |name, index|
          user = a8_video_user(8895 + index)
          id = 888_150 + index * 10
          blob = a8_blob(id)
          metadata = name == 'unidentified' ? {} : { identified: true }
          metadata[:analyzed] = true if name == 'shared_preidentified'
          blob.update!(metadata:)
          other = a8_video(user, id + 1, blob:) if name == 'shared_preidentified'
          %w[route_videos active_storage_attachments].each do |table|
            ActiveRecord::Base.connection.execute(
              "SELECT setval(pg_get_serial_sequence('#{table}', 'id'), #{id + 2}, false)"
            )
          end
          before = a8_video_graph(user)
          params = { route_video: { name: 'Metadata route', file: blob.signed_id, settings: a8_recipe } }
          a8_video_request(user, :post, '/route_videos', params:)
          expect(response.status).to eq(200), name
          saved = user.route_videos.find_by!(name: 'Metadata route')
          expect(saved.file.blob.id).to eq(id)
          expect(blob.reload.identified?).to be(true)
          if name == 'shared_preidentified'
            expect(blob.attachments.count).to eq(2)
            expect(other.reload.file.blob.id).to eq(id)
            expect(enqueued_jobs).to be_empty
          else
            expect(enqueued_jobs.map { _1[:job] }).to eq([ActiveStorage::AnalyzeJob])
          end
          request = { method: 'POST', path: '/route_videos', accept: 'text/vnd.turbo-stream.html',
                      params: params.deep_merge(route_video: { file: 'BLOB_SIGNED_ID' }), blob_id: id }
          a8_video_record("metadata_#{name}", user, before, request)
        end
      end
    end
  end

  def user_settings
    {
      9801 => { 'timezone' => 'Europe/Berlin', 'airtrail_url' => ' ' },
      9802 => { 'timezone' => 'America/New_York', 'maps' => { 'distance_unit' => 'mi' },
                'maps_maplibre_style' => 'dark', 'airtrail_url' => 'https://airtrail.example',
                'meters_between_routes' => '750', 'minutes_between_routes' => 90 },
      9803 => { 'timezone' => 'UTC' },
      9804 => { 'timezone' => 'Europe/Berlin' },
      9805 => { 'timezone' => 'Europe/Berlin' },
      9899 => { 'timezone' => 'Europe/Berlin' }
    }
  end

  def loop_path
    [[12.373468123456789, 51.33970012345678], [12.38, 51.345], [12.391234567890123, 51.34987654321098],
     [12.4, 51.34000000000001], [12.373468123456789, 51.33970012345678]]
  end

  def short_path = [[12.3712, 51.3391], [12.3801, 51.3422]]

  def line(lon, lat, count) = (0...count).map { |i| [lon + (i * 0.001), lat + (i * 0.0005)] }

  def trip(id, user_id, name, started, ended, opts = {})
    { id:, user_id:, name:, started_at: started, ended_at: ended, distance: opts[:distance],
      visited_countries: opts.fetch(:countries, []), path: opts[:path], recalculated_offset: opts[:recalculated] }
  end

  def many_trips
    (1..14).map do |n|
      trip(980_500 + n, 9805, format('Many %02d', n), (Time.utc(2024, 1, 1, 8) + n.days).iso8601(6),
           (Time.utc(2024, 1, 1, 18) + n.days).iso8601(6), distance: n.even? ? n * 1000 : nil,
           countries: n.even? ? ['Germany'] : [], path: n.even? ? line(12.3 + (n * 0.01), 51.3, 2) : nil)
    end
  end

  def trips
    [
      trip(980_101, 9801, 'Leipzig loop', '2026-05-09T06:00:00.000000Z', '2026-05-12T20:00:00.000000Z',
           distance: 12_345, countries: ['Germany'], path: loop_path, recalculated: 30),
      trip(980_102, 9801, 'Grenzgang <b>&</b> "Saale"', '2026-01-31T09:00:00.000000Z',
           '2026-02-02T07:00:00.000000Z', distance: 999_500, countries: %w[Germany France],
           path: line(12.35, 51.33, 3), recalculated: 3600),
      trip(980_103, 9801, 'No points', '2025-12-01T08:00:00.000000Z', '2025-12-01T18:00:00.000000Z', distance: 0),
      trip(980_104, 9801, 'Calculating', '2025-11-01T08:00:00.000000Z', '2025-11-02T08:00:00.000001Z',
           countries: {}),
      trip(980_105, 9801, 'Countryless', '2025-10-01T08:00:00.000000Z', '2025-10-01T09:30:00.000000Z',
           distance: 500, path: short_path),
      trip(980_106, 9801, 'Short hop', '2025-09-01T08:00:00.000000Z', '2025-09-01T09:00:00.000000Z',
           distance: 1499, countries: ['Germany'], path: short_path),
      trip(980_201, 9802, 'Auenwald walk', '2026-04-20T13:00:00.000000Z', '2026-04-21T02:30:00.000000Z',
           distance: 16_093, countries: ['United States'], path: line(12.33, 51.35, 4), recalculated: 3600),
      trip(980_301, 9803, 'Midnight run', '2026-06-01T22:00:00.000000Z', '2026-06-03T01:00:00.000000Z',
           distance: 800, countries: ['Germany'], path: line(12.36, 51.32, 2)),
      trip(980_302, 9803, 'Auwald notes', '2026-07-04T08:00:00.000000Z', '2026-07-05T18:00:00.000000Z',
           distance: 2500, countries: ['Germany'], path: short_path),
      *many_trips,
      trip(989_901, 9899, 'Foreign trip', '2026-05-09T06:00:00.000000Z', '2026-05-12T20:00:00.000000Z',
           distance: 1000, countries: ['Germany'], path: loop_path)
    ]
  end

  def point(id, user_id, time, lon, lat, opts = {})
    { id:, user_id:, timestamp: utc(time).to_i, lon:, lat:, tracker_id: opts[:tracker], source_id: opts[:source],
      anomaly: opts[:anomaly] }
  end

  def points
    [
      point(9_810_001, 9801, '2026-05-09T07:00:00Z', 12.37, 51.338, tracker: 'phone'),
      point(9_810_002, 9801, '2026-05-09T07:10:00Z', 12.375, 51.3395, tracker: 'phone'),
      point(9_810_003, 9801, '2026-05-09T07:20:00Z', 12.381, 51.341, tracker: 'phone'),
      point(9_810_004, 9801, '2026-05-09T07:30:00Z', 12.389, 51.344, tracker: 'phone'),
      point(9_810_005, 9801, '2026-05-10T06:00:00Z', 12.3712, 51.3391, tracker: 'phone'),
      point(9_810_006, 9801, '2026-05-10T06:05:00Z', 12.379, 51.342, source: 98_001),
      point(9_810_007, 9801, '2026-05-10T06:15:00Z', 12.376, 51.3405, tracker: 'phone'),
      point(9_810_008, 9801, '2026-05-10T06:20:00Z', 12.383, 51.345, source: 98_001),
      point(9_810_009, 9801, '2026-05-10T06:30:00Z', 12.3801, 51.3422, tracker: 'phone'),
      point(9_810_010, 9801, '2026-05-10T08:00:00Z', 12.39, 51.36, tracker: 'phone', anomaly: true),
      point(9_810_011, 9801, '2026-05-10T09:00:00Z', 12.39, 51.35, tracker: 'phone'),
      point(9_810_012, 9801, '2026-05-10T09:10:00Z', 12.395, 51.353, tracker: 'phone'),
      point(9_810_013, 9801, '2026-05-10T12:00:00Z', 12.4, 51.33, source: 98_001),
      point(9_810_014, 9801, '2026-05-10T12:10:00Z', 12.41, 51.33, source: 98_001),
      point(9_810_015, 9801, '2026-05-10T15:00:00Z', 12.42, 51.325, source: 98_002),
      point(9_810_016, 9801, '2026-05-10T22:30:00Z', 12.37, 51.34, tracker: 'phone'),
      point(9_810_017, 9801, '2026-05-10T22:35:00Z', 12.3701, 51.3403, tracker: 'phone'),
      point(9_810_101, 9801, '2026-02-01T10:00:00Z', 12.35, 51.33, tracker: 'phone'),
      point(9_810_102, 9801, '2026-02-01T11:00:00Z', 12.35, 51.34, tracker: 'phone'),
      point(9_820_001, 9802, '2026-04-20T14:00:00Z', 12.33, 51.35, tracker: 'pixel'),
      point(9_820_002, 9802, '2026-04-20T15:00:00Z', 12.33, 51.37, tracker: 'pixel'),
      point(9_830_001, 9803, '2026-06-01T22:10:00Z', 12.36, 51.32),
      point(9_830_002, 9803, '2026-06-01T22:12:00Z', 12.3601, 51.3201),
      point(9_830_003, 9803, '2026-06-03T00:10:00Z', 12.36, 51.32),
      point(9_830_004, 9803, '2026-06-03T00:40:00Z', 12.36, 51.335),
      point(9_890_001, 9899, '2026-05-09T07:05:00Z', 12.37, 51.338, tracker: 'phone'),
      point(9_890_002, 9899, '2026-05-10T06:10:00Z', 12.379, 51.342, tracker: 'phone')
    ]
  end

  def countries
    [{ name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU' }, { name: 'France', iso_a2: 'FR', iso_a3: 'FRA' },
     { name: 'United States', iso_a2: 'US', iso_a3: 'USA' }]
  end

  def sources = [{ id: 98_001, tracker_id: 'watch' }, { id: 98_002, tracker_id: nil }]

  def notes
    [{ id: 9_811, trip_id: 980_101, user_id: 9801, noted_at: '2026-05-10T12:00:00Z',
       body: "Morgenkaffee <b>am</b> See\nthen the Auensee" },
     { id: 9_812, trip_id: 980_101, user_id: 9801, noted_at: '2026-05-20T12:00:00Z', body: 'Outside the trip' },
     { id: 9_833, trip_id: 980_302, user_id: 9803, noted_at: '2026-07-05T12:00:00Z',
       body: %(Picknick am "Auensee" & 'Rosental') },
     { id: 9_891, trip_id: 989_901, user_id: 9899, noted_at: '2026-05-10T12:00:00Z', body: 'Foreign note' }]
  end

  def described
    '<h1>Leipzig &amp; the Auwald</h1><div>From the <strong>Rosental</strong> <em>along</em> the ' \
      '<del>Elster</del> Pleiße<br>two&nbsp;&nbsp;spaces, "quotes" and 3 &lt; 4 &gt; 2</div>' \
      '<blockquote>Leise rauscht der Fluss</blockquote><ul><li>Rosental<ul><li>Zoo</li></ul></li><li>' \
      '<a href="https://www.leipzig.de/freizeit?x=1&amp;y=2#auwald">Auwald</a></li></ul><ol><li>Auensee</li>' \
      "</ol><pre>12.3712 51.3391\n12.3801 51.3422</pre>"
  end

  def rich_texts = [{ trip_id: 980_302, body: described }]

  def shared_links
    [{ id: 'a8510000-0000-4000-8000-000000000001', resource_type: 0, trip_id: 980_101, user_id: 9801,
       revoked: false, expires_offset: 7.days.to_i },
     { id: 'a8510000-0000-4000-8000-000000000002', resource_type: 0, trip_id: 980_201, user_id: 9802,
       revoked: true, expires_offset: nil },
     { id: 'a8510000-0000-4000-8000-000000000003', resource_type: 0, trip_id: 980_201, user_id: 9802,
       revoked: false, expires_offset: -1.day.to_i },
     { id: 'a8510000-0000-4000-8000-000000000004', resource_type: 1, trip_id: 980_102, user_id: 9801,
       revoked: false, expires_offset: nil },
     { id: 'a8510000-0000-4000-8000-000000000005', resource_type: 0, trip_id: 989_901, user_id: 9899,
       revoked: false, expires_offset: nil }]
  end

  def posters
    [{ id: 9_831, user_id: 9803, name: 'Leipzig poster', status: 0, created_at: '2026-09-20T10:00:00.000000Z' }]
  end

  def route_videos
    [{ id: 9_832, user_id: 9803, name: 'Run video', status: 1, expired_at: '2026-09-01T18:30:00.000000Z',
       settings: { 'format' => 'landscape' }, created_at: '2026-08-20T10:00:00.000000Z' }]
  end

  def create_users!
    user_settings.map do |id, settings|
      user = create(:user, id:, email: "a8-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge(settings).merge('onboarding_completed' => true),
                          api_key: "a8-k-#{id}")
      user.reload
      { id:, email: user.email, settings: user.settings, api_key: user.api_key }
    end
  end

  def insert!
    Country.insert_all(countries.map { |c| c.merge(created_at: now, updated_at: now) })
    PointSource.insert_all(sources.map { |s| s.merge(digest: "a8s1#{s[:id]}", created_at: now, updated_at: now) })
    Trip.insert_all(trips.map do |t|
      t.slice(:id, :user_id, :name, :distance, :visited_countries)
       .merge(started_at: utc(t[:started_at]), ended_at: utc(t[:ended_at]),
              path: t[:path] && "LINESTRING(#{t[:path].map { |x, y| "#{x} #{y}" }.join(', ')})",
              last_recalculated_at: t[:recalculated_offset] && (now - t[:recalculated_offset]),
              created_at: now, updated_at: now)
    end)
    Point.insert_all(points.map do |p|
      p.slice(:id, :user_id, :timestamp, :tracker_id, :source_id, :anomaly)
       .merge(lonlat: "POINT(#{p[:lon]} #{p[:lat]})", created_at: now, updated_at: now)
    end)
    Note.insert_all(notes.map do |n|
      { id: n[:id], attachable_type: 'Trip', attachable_id: n[:trip_id], user_id: n[:user_id], body: n[:body],
        noted_at: utc(n[:noted_at]), created_at: now, updated_at: now }
    end)
    ActionText::RichText.insert_all(rich_texts.map do |r|
      { record_type: 'Trip', record_id: r[:trip_id], name: 'description', body: r[:body], created_at: now,
        updated_at: now }
    end)
    SharedLink.insert_all(shared_links.map do |l|
      { id: l[:id], name: 'Fixture link', resource_type: SharedLink.resource_types.key(l[:resource_type]),
        resource_id: l[:trip_id], user_id: l[:user_id], revoked_at: l[:revoked] ? now - 1.day : nil,
        expires_at: l[:expires_offset] && (now + l[:expires_offset]), settings: {}, created_at: now, updated_at: now }
    end)
    Poster.insert_all(posters.map do |p|
      p.slice(:id, :user_id, :name).merge(status: Poster.statuses.key(p[:status]), settings: {},
                                          created_at: utc(p[:created_at]), updated_at: utc(p[:created_at]))
    end)
    RouteVideo.insert_all(route_videos.map do |v|
      v.slice(:id, :user_id, :name, :settings).merge(status: RouteVideo.statuses.key(v[:status]),
                                                     expired_at: utc(v[:expired_at]), created_at: utc(v[:created_at]),
                                                     updated_at: utc(v[:created_at]))
    end)
  end

  def pages
    [
      ['index_states', 9801, '/trips'], ['index_ny', 9802, '/trips'], ['index_empty', 9804, '/trips'],
      ['index_many_page1', 9805, '/trips'], ['index_many_page2', 9805, '/trips?page=2'],
      ['index_many_page3', 9805, '/trips?page=3'], ['index_many_page0', 9805, '/trips?page=0'],
      ['index_many_page_negative', 9805, '/trips?page=-1'], ['index_many_page_2abc', 9805, '/trips?page=2abc'],
      ['index_many_page_out', 9805, '/trips?page=4'], ['index_many_extra_param', 9805, '/trips?page=2&view=cards'],
      ['show_leipzig', 9801, '/trips/980101'], ['show_grenzgang', 9801, '/trips/980102'],
      ['show_short_hop', 9801, '/trips/980106'], ['show_ny', 9802, '/trips/980201'],
      ['show_utc', 9803, '/trips/980301'], ['show_described', 9803, '/trips/980302']
    ]
  end

  def capture(name, user_id, path)
    Rails.cache.clear
    sign_in User.find(user_id)
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    File.write(dir.join("pages/#{name}.html"), doc.at_css('body > div.container > div.w-full > div.flex').inner_html)
    sign_out :user
    { name:, user_id:, path:, title: doc.at_css('title').text }
  end

  it 'writes the trips pages and the seed they render' do
    expect(Rails.application.secret_key_base).to eq(secret)
    expect(ENV.values_at('TIME_ZONE', 'PRINT_ORDER_URL')).to eq([nil, nil])

    travel_to now do
      users = create_users!
      insert!
      write_json('pages.json', { pages: pages.map { |name, user_id, path| capture(name, user_id, path) } })
      write_json('seed.json', { users:, countries:, sources:, trips:, points:, notes:, rich_texts:, shared_links:,
                                posters:, route_videos: })
    end
  end

  it 'writes the day-data corpus' do
    travel_to now do
      create_users!
      insert!
      cases = [980_101, 980_102, 980_106, 980_201, 980_301].map do |id|
        trip = Trip.find(id)
        zone = trip.user.timezone_iana
        { trip_id: id, user_id: trip.user_id, from: trip.started_at.to_i, to: trip.ended_at.to_i,
          gap: trip.user.safe_settings.minutes_between_routes * 60, iana: zone,
          windows_json: trip.primary_device_windows.to_json,
          stats: trip.day_stats(zone).sort.map do |day, stat|
            { day: day.iso8601, first: stat[:first_time].strftime('%Y-%m-%dT%H:%M:%S'),
              last: stat[:last_time].strftime('%Y-%m-%dT%H:%M:%S'), distance_m: stat[:distance_m].round(6) }
          end }
      end
      write_json('windows.json', { trips: cases })
    end
  end

  it 'writes the duration and precision corpus' do
    zones = %w[Europe/Berlin America/New_York UTC Asia/Kathmandu]
    spans = [%w[2026-05-09T06:00:00Z 2026-05-12T20:00:00Z], %w[2026-01-31T09:00:00Z 2026-03-02T07:00:00Z],
             %w[2026-01-31T09:00:00Z 2026-02-02T07:00:00Z], %w[2026-04-30T10:00:00Z 2026-05-01T09:00:00Z],
             %w[2025-12-31T23:30:00Z 2026-01-01T00:15:00Z], %w[2026-02-15T12:00:00Z 2027-04-18T16:00:00Z],
             %w[2026-03-20T09:00:00Z 2026-04-10T07:00:00Z], %w[2026-10-20T12:00:00Z 2026-11-18T08:00:00Z],
             %w[2026-10-28T08:00:00Z 2026-11-25T01:30:00Z],
             %w[2026-06-01T10:00:00Z 2026-06-01T10:59:00Z], %w[2026-06-01T10:00:00Z 2026-06-01T10:00:00Z]]
    durations = zones.product(spans).map do |zone, (from, to)|
      text = Time.use_zone(zone) { helper.trip_duration(Trip.new(started_at: utc(from), ended_at: utc(to))) }
      { zone:, started_at: from, ended_at: to, text: }
    end
    values = [1.0, 1.05, 1.15, 1.25, 1.35, 2.675, 9.95, 12.25, 12.35, 99.95, 100.0, 1234.56, 3.14159,
              10.049999999999999, 10.05, 7.000000000000001, 1.0000000000000002, 1.0e21, 123_456_789.25]
    precision = values.map { |value| { value:, text: helper.number_with_precision(value, precision: 1) } }
    write_json('format.json', { durations:, precision: })
  end

  it 'raises for a previous-month wall time inside a DST gap, which Phoenix hands back' do
    trip = Trip.new(started_at: utc('2026-03-30T08:00:00Z'), ended_at: utc('2026-04-29T00:30:00Z'))
    expect { Time.use_zone('Europe/Berlin') { helper.trip_duration(trip) } }.to raise_error(StandardError)
  end

  it 'writes the trip stream-name corpus' do
    expect(Rails.application.secret_key_base).to eq(secret)
    signed = [980_101, 980_301, 1, 123_456_789].map do |id|
      { trip_id: id, signed: Turbo::StreamsChannel.signed_stream_name(Trip.new(id:)) }
    end
    write_json('streams.json', { secret:, trips: signed })
  end
end
