# frozen_string_literal: true

module VideoExports
  class RequestRender
    class RenderError < StandardError; end

    MAX_COORDINATES = 50_000

    def initialize(video_export:)
      @video_export = video_export
    end

    def call
      payload = render_payload
      Rails.logger.info '[VideoExports::RequestRender] Sending render request: ' \
                        "coordinates=#{payload[:coordinates].length}, " \
                        "callback_url=#{payload[:callback_url].present?}, " \
                        "config=#{payload[:config].present?}"

      raise RenderError, 'No coordinates found for the given date range' if payload[:coordinates].empty?

      response = post_render_request(payload)
      handle_response(response)
    end

    private

    attr_reader :video_export

    def post_render_request(payload)
      uri = URI.parse("#{video_service_url.chomp('/')}/api/render")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 30
      begin
        http.ipaddr = Resolv::DNS.open { |dns| dns.getresource(uri.host, Resolv::DNS::Resource::IN::A).address.to_s }
      rescue Resolv::ResolvError
        # Fall back to default resolution (e.g. Docker internal hostnames)
      end

      headers = { 'Content-Type' => 'application/json' }
      token = ENV['VIDEO_SERVICE_AUTH_TOKEN']
      headers['Authorization'] = "Bearer #{token}" if token.present?
      request = Net::HTTP::Post.new(uri.path, headers)
      request.body = payload.to_json

      http.request(request)
    end

    def handle_response(response)
      return if response.is_a?(Net::HTTPSuccess)

      body = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end
      raise RenderError, "Video service returned #{response.code}: #{body['error'] || response.message}"
    end

    def render_payload
      urls = callback_urls
      {
        video_export_id: video_export.id,
        callback_url: urls.first,
        callback_urls: urls,
        config: video_export.config,
        coordinates: track_coordinates
      }
    end

    def track_coordinates
      points = if video_export.track_id
                 track_points_for(video_export.track)
               else
                 points_for_date_range
               end

      # Fall back to the lonlat geography column when the longitude/latitude
      # decimal columns are NULL (happens for some import sources)
      coords = points.pluck(
        Arel.sql('COALESCE(longitude, ST_X(lonlat::geometry))'),
        Arel.sql('COALESCE(latitude, ST_Y(lonlat::geometry))'),
        :timestamp
      ).filter_map { |lon, lat, ts| [lon.to_f, lat.to_f, ts] if lon && lat }

      downsample(coords)
    end

    # Matches the fallback pattern from Api::V1::Tracks::PointsController:
    # first try points linked via track_id, then fall back to time range
    def track_points_for(track)
      points = track.points.order(:timestamp)
      return points.limit(MAX_COORDINATES * 2) if points.exists?

      video_export.user.points
                  .where(timestamp: track.start_at.to_i..track.end_at.to_i)
                  .order(:timestamp)
                  .limit(MAX_COORDINATES * 2)
    end

    def points_for_date_range
      video_export.user.points
                  .where(timestamp: video_export.start_at.to_i..video_export.end_at.to_i)
                  .order(:timestamp)
                  .limit(MAX_COORDINATES * 2)
    end

    # Evenly downsample coordinates to MAX_COORDINATES, preserving first and last
    def downsample(coords)
      return coords if coords.length <= MAX_COORDINATES

      step = coords.length.to_f / (MAX_COORDINATES - 1)
      result = (0...MAX_COORDINATES - 1).map { |i| coords[(i * step).round] }
      result << coords.last
      result.uniq
    end

    def callback_urls
      token = VideoExports::CallbackToken.generate(video_export.id, video_export.callback_nonce)
      callback_path = "/api/v1/video_exports/#{video_export.id}/callback?token=#{token}"
      protocol = ENV.fetch('APPLICATION_PROTOCOL', 'http')
      hosts = ENV.fetch('APPLICATION_HOSTS', 'localhost').split(',').map(&:strip).reject(&:blank?)
      hosts.reject! { |h| h.match?(/\Alocalhost(:\d+)?\z/) || h.match?(/\A127\.0\.0\.1(:\d+)?\z/) }

      # Build a URL for each configured host
      urls = hosts.map { |host| "#{protocol}://#{host}#{callback_path}" }

      # Fall back to APPLICATION_HOST for backwards compatibility
      if urls.empty?
        app_url = ENV.fetch('APPLICATION_HOST', 'http://localhost:3000')
        app_url = "https://#{app_url}" unless app_url.start_with?('http://', 'https://')
        urls = ["#{app_url}#{callback_path}"]
      end

      urls
    end

    def video_service_url
      ENV.fetch('VIDEO_SERVICE_URL', 'http://dawarich_video:3100')
    end
  end
end
