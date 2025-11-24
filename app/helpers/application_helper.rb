# frozen_string_literal: true

module ApplicationHelper
  def flash_alert_class(type)
    case type.to_sym
    when :notice, :success then 'alert-success'
    when :alert, :error then 'alert-error'
    when :warning then 'alert-warning'
    when :info then 'alert-info'
    else 'alert-info'
    end
  end

  def flash_icon(type)
    case type.to_sym
    when :notice, :success then icon 'circle-check'
    when :alert, :error then icon 'circle-x'
    when :warning then icon 'circle-alert'
    else
      icon 'info'
    end
  end

  def year_timespan(year)
    start_at = DateTime.new(year).beginning_of_year.strftime('%Y-%m-%dT%H:%M')
    end_at = DateTime.new(year).end_of_year.strftime('%Y-%m-%dT%H:%M')

    { start_at:, end_at: }
  end

  def header_colors
    %w[info success warning error accent secondary primary]
  end

  def new_version_available?
    CheckAppVersion.new.call
  end

  def app_theme
    current_user&.theme == 'light' ? 'light' : 'dark'
  end

  def active_class?(link_path)
    'btn-active' if current_page?(link_path)
  end

  def full_title(page_title = '')
    base_title = 'Dawarich'
    page_title.empty? ? base_title : "#{page_title} | #{base_title}"
  end

  def active_tab?(link_path)
    'tab-active' if current_page?(link_path)
  end

  def active_visit_places_tab?(controller_name)
    'tab-active' if current_page?(controller: controller_name)
  end

  def notification_link_color(notification)
    return 'text-gray-600' if notification.read?

    'text-blue-600'
  end

  def human_date(date)
    date.strftime('%e %B %Y')
  end

  def human_datetime(datetime)
    return unless datetime

    content_tag(
      :span,
      datetime.strftime('%e %b %Y, %H:%M'),
      class: 'tooltip',
      data: { tip: datetime.iso8601 }
    )
  end

  def human_datetime_with_seconds(datetime)
    return unless datetime

    content_tag(
      :span,
      datetime.strftime('%e %b %Y, %H:%M:%S'),
      class: 'tooltip',
      data: { tip: datetime.iso8601 }
    )
  end

  def speed_text_color(speed)
    return 'text-default' if speed.to_i >= 0

    'text-red-500'
  end

  def point_speed(speed)
    return speed if speed.to_i <= 0

    speed * 3.6
  end

  def days_left(active_until)
    return unless active_until

    time_words = distance_of_time_in_words(Time.zone.now, active_until)

    content_tag(
      :span,
      time_words,
      class: 'tooltip',
      data: { tip: "Expires on #{active_until.iso8601}" }
    )
  end

  def onboarding_modal_showable?(user)
    user.trial_state?
  end

  def trial_button_class(user)
    case (user.active_until.to_date - Time.current.to_date).to_i
    when 5..8
      'btn-info'
    when 2...5
      'btn-warning'
    when 0...2
      'btn-error'
    else
      'btn-success'
    end
  end

  def oauth_provider_name(provider)
    return OIDC_PROVIDER_NAME if provider == :openid_connect

    OmniAuth::Utils.camelize(provider)
  end

  def email_password_registration_enabled?
    return true unless DawarichSettings.self_hosted?

    ALLOW_EMAIL_PASSWORD_REGISTRATION
  end
end
