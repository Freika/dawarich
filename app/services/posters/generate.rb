# frozen_string_literal: true

module Posters
  class Generate
    MAX_DISTANCE = 5_000_000
    MIN_DISTANCE = 500
    MIN_ROUTE_WIDTH = 0.5
    MAX_ROUTE_WIDTH = 3.0
    TILE_PIXELS = 512
    METERS_PER_PIXEL_AT_ZOOM_0 = 40_075_016.686 / TILE_PIXELS

    def initialize(poster)
      @poster = poster
    end

    def call
      return if @poster.completed?

      @poster.update!(status: :processing)

      track = build_track
      return fail_with(I18n.t('services.posters.generate.no_location_data')) if track.nil?

      return fail_with(I18n.t('services.posters.generate.track_outside_area')) unless track_intersects_area?(track)

      render_natively(track)
      @poster.update!(status: :completed)
    rescue StandardError => e
      ExceptionReporter.call(e, "Poster render failed for poster #{@poster.id}")
      fail_with(I18n.t('services.posters.generate.failed'))
    end

    private

    def build_track
      builder_class = @poster.settings['source'] == 'tracks' ? Posters::TracksBuilder : Posters::TrackBuilder

      builder_class.new(
        user: @poster.user,
        start_at: Time.zone.parse(@poster.settings['start_at']),
        end_at: Time.zone.parse(@poster.settings['end_at'])
      ).call
    end

    def render_natively(track)
      record_progress('drawing_map')
      result = Posters::NativeRenderer.new(
        poster: @poster,
        track: track,
        distance: distance,
        route_opacity: route_opacity,
        route_width: route_width,
        subtitle: subtitle
      ).call
      attach_image(result[:png])
      attach_print_pdf(result[:pdf])
    end

    def route_opacity
      raw = @poster.settings['route_opacity'].to_f
      raw /= 100.0 if raw > 1
      raw = 1.0 if raw <= 0
      raw.clamp(0.05, 1.0)
    end

    def route_width
      raw = @poster.settings.fetch('route_width', 100).to_f
      return 1.0 if raw <= 0

      (raw / 100.0).clamp(MIN_ROUTE_WIDTH, MAX_ROUTE_WIDTH)
    end

    def distance
      @poster.settings.fetch('distance', 6000).to_i.clamp(MIN_DISTANCE, MAX_DISTANCE)
    end

    def track_intersects_area?(track)
      lat = @poster.settings['lat'].to_f
      lon = @poster.settings['lon'].to_f
      south, north = frame_latitude_bounds(lat)
      lon_delta = frame_longitude_delta(lat)

      track['coordinates'].any? do |segment|
        segment.any? do |pt_lon, pt_lat|
          pt_lat.between?(south, north) && longitude_within?(pt_lon, lon, lon_delta)
        end
      end
    end

    def frame_latitude_bounds(lat)
      half = Math::PI * frame_size[:height] / frame_world_pixels(lat)
      centre = Math.log(Math.tan((Math::PI / 4) + (lat * Math::PI / 360)))

      [mercator_to_latitude(centre - half), mercator_to_latitude(centre + half)]
    end

    def frame_longitude_delta(lat)
      180.0 * frame_size[:width] / frame_world_pixels(lat)
    end

    def frame_world_pixels(lat)
      meters_per_pixel = (2 * distance / 3.0) / frame_size[:height]
      zoom = Math.log2(METERS_PER_PIXEL_AT_ZOOM_0 * cos_latitude(lat) / meters_per_pixel)

      TILE_PIXELS * (2**zoom)
    end

    def mercator_to_latitude(mercator_y)
      ((2 * Math.atan(Math::E**mercator_y)) - (Math::PI / 2)) * 180 / Math::PI
    end

    def cos_latitude(lat)
      Math.cos(lat * Math::PI / 180).abs.clamp(0.01, 1.0)
    end

    def longitude_within?(pt_lon, lon, lon_delta)
      return true if lon_delta >= 180.0

      (((pt_lon - lon + 180.0) % 360.0) - 180.0).abs <= lon_delta
    end

    def frame_size
      Posters::NativeRenderer::SIZE
    end

    def subtitle
      start_at = Time.zone.parse(@poster.settings['start_at']).utc
      end_at = Time.zone.parse(@poster.settings['end_at']).utc

      "#{start_at.strftime('%-d %b %Y')} – #{end_at.strftime('%-d %b %Y')}"
    end

    def attach_image(image)
      @poster.image.attach(
        io: StringIO.new(image),
        filename: "poster_#{@poster.id}.png",
        content_type: 'image/png'
      )
    end

    def attach_print_pdf(pdf)
      @poster.print_pdf.attach(
        io: StringIO.new(pdf),
        filename: "poster_#{@poster.id}.pdf",
        content_type: 'application/pdf'
      )
    end

    def fail_with(message)
      @poster.update!(status: :failed, settings: @poster.settings.merge('error' => message))
    end

    def record_progress(phase)
      return if phase.blank? || @poster.settings['progress_phase'] == phase

      @poster.update!(settings: @poster.settings.merge('progress_phase' => phase))
    end
  end
end
