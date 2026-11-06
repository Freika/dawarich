# frozen_string_literal: true

module SharedLinksHelper
  def formatted_date_range(start_date, end_date)
    start_date = Date.parse(start_date.to_s) unless start_date.is_a?(Date)
    end_date   = Date.parse(end_date.to_s)   unless end_date.is_a?(Date)

    if start_date == end_date
      I18n.l(start_date, format: :month_day_year)
    elsif Current.date_time_preferences.date_format != 'auto'
      I18n.t(
        'helpers.shared_links.date_ranges.different_years',
        start_date: I18n.l(start_date, format: :medium),
        end_date: I18n.l(end_date, format: :medium)
      )
    elsif start_date.year == end_date.year && start_date.month == end_date.month
      I18n.t(
        'helpers.shared_links.date_ranges.same_month',
        start_date: I18n.l(start_date, format: :month_day),
        end_date: I18n.l(end_date, format: :day_year)
      )
    elsif start_date.year == end_date.year
      I18n.t(
        'helpers.shared_links.date_ranges.same_year',
        start_date: I18n.l(start_date, format: :month_day),
        end_date: I18n.l(end_date, format: :month_day_year)
      )
    else
      I18n.t(
        'helpers.shared_links.date_ranges.different_years',
        start_date: I18n.l(start_date, format: :medium),
        end_date: I18n.l(end_date, format: :medium)
      )
    end
  end

  def timeline_share_subtitle(share)
    return nil unless share&.timeline?

    range = formatted_date_range(share.settings['start_date'], share.settings['end_date'])
    I18n.t('helpers.shared_links.timeline_subtitle', range:)
  end

  def trip_share_subtitle(trip)
    I18n.t('helpers.shared_links.trip_subtitle', trip: trip.name)
  end

  def track_share_label(track, unit)
    mode = track.dominant_mode.presence
    mode = mode ? I18n.t("transportation_modes.#{mode}") : I18n.t('helpers.shared_links.track')
    zone = track.user.timezone_iana.presence || 'UTC'
    date = I18n.l(track.start_at.in_time_zone(zone).to_date, format: :day_month_year_abbreviated)
    distance = track.distance_in_unit(unit).round
    I18n.t('helpers.shared_links.track_label', mode:, date:, distance:, unit:)
  end

  def shared_link_sections(share)
    keys = case share.resource_type
           when 'trip' then %w[show_route show_stats show_days show_day_notes show_description show_photos]
           when 'track' then %w[show_route show_stats show_photos]
           when 'timeline' then %w[show_route show_photos]
           when 'live' then %w[show_route]
           else []
           end
    context = SharedLinkContext.new(share)
    keys.index_with { |key| context.public_send("#{key}?") }
  end

  def shared_link_expiration_label(share)
    return t('ux_p2.sharing.no_expiry') unless share.expires_at

    time = share.expires_at.in_time_zone(share.user.timezone_iana)
    safe_join([human_datetime_with_seconds(time, share.user.timezone_iana), " (#{share.user.timezone_iana})"])
  end

  def shared_link_management_paths(share)
    case share.resource_type
    when 'trip'
      { regenerate: regenerate_trip_share_link_path(share.resource_id),
        regenerate_phrase: regenerate_phrase_trip_share_link_path(share.resource_id),
        revoke: revoke_trip_share_link_path(share.resource_id) }
    when 'track'
      { regenerate: regenerate_track_share_link_path(share.resource_id),
        regenerate_phrase: regenerate_phrase_track_share_link_path(share.resource_id),
        revoke: revoke_track_share_link_path(share.resource_id) }
    else
      prefix = share.timeline? ? 'timeline' : 'live'
      { regenerate: public_send("regenerate_share_links_#{prefix}_path"),
        regenerate_phrase: public_send("regenerate_phrase_share_links_#{prefix}_path"),
        revoke: public_send("revoke_share_links_#{prefix}_path") }
    end
  end

  PUBLIC_SHARE_CTA_BASE = 'https://dawarich.app'

  def public_share_cta_url(utm_content, path: '/')
    utm = {
      utm_source: 'dawarich_share',
      utm_medium: 'public_share',
      utm_campaign: 'cloud',
      utm_content: utm_content
    }.to_query
    "#{PUBLIC_SHARE_CTA_BASE}#{path}?#{utm}"
  end
end
