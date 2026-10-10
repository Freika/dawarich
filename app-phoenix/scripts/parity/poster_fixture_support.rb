# frozen_string_literal: true

module PosterFixtureSupport
  def poster_actor(id)
    user = create(:user, id:, email: "a9fpl-poster-#{id}@dawarich.test", skip_auto_trial: true,
                         changelog_consent: :declined)
    user.update_columns(settings: { 'locale' => 'en', 'timezone' => 'UTC', 'onboarding_completed' => true },
                        api_key: "a9fpl-fixture-#{id}")
    user.reload
  end

  def poster_settings
    { 'lat' => '51.3397', 'lon' => '12.3731', 'distance' => '6000', 'theme' => 'terracotta',
      'start_at' => (now - 1.day).iso8601, 'end_at' => now.iso8601, 'source' => 'points' }
  end

  def fixture_poster(user, id, **extra)
    Poster.create!({ id:, user:, name: 'Leipzig Fixture Poster', status: :created,
                     settings: poster_settings, created_at: now, updated_at: now }.merge(extra))
  end

  def poster_point(user, id, offset, lonlat = 'POINT(12.3731 51.3397)', anomaly: false)
    Point.insert!({ id:, user_id: user.id, timestamp: offset && now.to_i + offset, lonlat:, anomaly:,
                    created_at: now, updated_at: now })
  end

  def poster_track(user)
    Posters::TrackBuilder.new(user:, start_at: now - 1.day, end_at: now).call
  end

  def poster_rows(user, table)
    sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE user_id = #{Integer(user.id)} ORDER BY id"
    rows = ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }
    return rows unless table == 'tracks'

    rows.map do |row|
      row.except(*%w[map_matched_at map_matching_data map_matching_input_digest map_matching_status matched_path])
    end
  end

  def poster_row(poster)
    return unless poster

    { 'id' => poster.id, 'user_id' => poster.user_id, 'name' => poster.name,
      'status' => Poster.statuses[poster.status], 'settings' => poster.settings,
      'created_at' => poster.created_at.utc.iso8601(6), 'updated_at' => poster.updated_at.utc.iso8601(6) }
  end

  def poster_attachments(poster)
    return [] unless poster

    ActiveStorage::Attachment.where(record: poster).order(:name).map do |attachment|
      blob = attachment.blob
      { 'name' => attachment.name, 'record_type' => attachment.record_type, 'record_id' => attachment.record_id,
        'filename' => blob.filename.to_s, 'content_type' => blob.content_type, 'byte_size' => blob.byte_size,
        'metadata' => blob.metadata, 'checksum' => blob.checksum,
        'bytes_base64' => Base64.strict_encode64(blob.download) }
    end
  end

  def poster_html(html)
    doc = Nokogiri::HTML5.fragment(html)
    doc.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
    doc.css('[data-exception-object-id]').each { |node| node['data-exception-object-id'] = 'EXCEPTION' }
    doc.css('#session_dump pre').each { |dump| dump.content = 'SESSION' }
    doc.css('#env_dump pre').each do |dump|
      dump.content = dump.content.gsub(/(HTTP_X_CSRF_TOKEN: )"[^"]*"/, '\1"CSRF"')
    end
    FixtureRecording.normalize(doc.to_html)
                    .gsub(%r{(/rails/active_storage/blobs/(?:redirect|proxy)/)[^/"?]+}, '\1SIGNED')
  end

  def poster_card(poster)
    I18n.with_locale(poster.user.locale) do
      poster_html(ApplicationController.render(partial: 'posters/poster', locals: { poster: }))
    end
  end

  def write_poster(name, data, html = '')
    files = { "#{name}.json" => "#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n",
              "#{name}.html" => html }
    files.each do |filename, bytes|
      bytes = FixtureRecording.normalize(bytes)
      if ENV['WRITE_POSTER_FIXTURES'] == '1'
        File.write(dir.join(filename), bytes)
      else
        matches = File.exist?(dir.join(filename)) && File.binread(dir.join(filename)) == bytes.b
        expect(matches).to be(true), "#{filename} differs; regenerate with WRITE_POSTER_FIXTURES=1"
      end
    end
    data
  end

  def poster_geometry(generator, track)
    geometry = { 'distance' => generator.send(:distance), 'route_opacity' => generator.send(:route_opacity),
                 'route_width' => generator.send(:route_width), 'size' => Posters::NativeRenderer::SIZE,
                 'print' => Posters::NativeRenderer::PRINT, 'timeout' => Posters::NativeRenderer::RENDER_TIMEOUT }
    geometry['intersects'] = track && generator.send(:track_intersects_area?, track)
    geometry
  rescue StandardError => e
    geometry.merge('intersection_error' => e.class.name)
  end

  def capture_poster_generation(name, poster)
    track = begin
      Posters::Generate.new(poster).send(:build_track)
    rescue StandardError
      nil
    end
    before = poster_row(poster)
    blob_count = ActiveStorage::Blob.count
    geometry = poster_geometry(Posters::Generate.new(poster), track)
    events = []
    observer = ActiveSupport::Notifications.subscribe('broadcast.action_cable') do |_name, _start, _end, _id, payload|
      events << { 'stream' => payload[:broadcasting], 'html' => poster_html(payload[:message].to_s) }
    end
    Posters::CreateJob.perform_now(poster.id)
    current = Poster.find_by(id: poster.id)
    image = current&.image
    job = image&.attached? ? JSON.parse(image.download) : nil
    data = { 'now' => now.iso8601, 'actor_id' => poster.user_id, 'locale' => poster.user.locale.to_s,
             'before' => before, 'after' => poster_row(current), 'track' => track, 'geometry' => geometry,
             'points' => poster_rows(poster.user, 'points'), 'tracks' => poster_rows(poster.user, 'tracks'),
             'render_job' => job, 'attachments' => poster_attachments(current), 'events' => events,
             'blob_delta' => ActiveStorage::Blob.count - blob_count,
             'time_zone' => Time.zone.name, 'parsed_times' => parsed_poster_times(poster.settings) }
    write_poster(name, data, current ? poster_card(current) : '')
  ensure
    ActiveSupport::Notifications.unsubscribe(observer) if observer
  end

  def parsed_poster_times(settings)
    %w[start_at end_at].to_h do |key|
      parsed = begin
        Time.zone.parse(settings[key])&.utc&.iso8601(6)
      rescue StandardError => e
        { 'error' => e.class.name }
      end
      [key, parsed]
    end
  end

  def capture_poster_request(name, user, verb, path, params: {}, turbo: false)
    reset!
    sign_in user.reload
    get '/family/new'
    csrf = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    headers = { 'X-CSRF-Token' => csrf, 'Accept' => turbo ? 'text/vnd.turbo-stream.html' : 'text/html' }
    before = user.posters.order(:id).map { |poster| poster_row(poster) }
    send(verb, path, params:, headers:)
    jobs = enqueued_jobs.select { |job| job[:job] == Posters::CreateJob }.map do |job|
      { 'command' => job[:job].name, 'queue' => job[:queue], 'args' => job[:args], 'locale' => job['locale'] }
    end
    posters_after = user.posters.order(:id).map { |poster| poster_row(poster) }
    data = { 'now' => now.iso8601, 'actor_id' => user.id, 'locale' => user.locale.to_s,
             'verb' => verb.to_s.upcase, 'path' => path, 'params' => params.deep_stringify_keys, 'turbo' => turbo,
             'status' => response.status, 'content_type' => response.media_type,
             'location' => response.headers['Location'], 'flash' => flash.to_hash,
             'before' => before, 'after' => posters_after, 'jobs' => jobs }
    write_poster(name, data, poster_html(response.body))
    sign_out user
    data
  end
end
