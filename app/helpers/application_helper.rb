# frozen_string_literal: true

module ApplicationHelper
  def flash_alert_class(type)
    case type.to_sym
    when :notice, :success
      'alert-success'
    when :alert, :error
      'alert-error'
    when :warning
      'alert-warning'
    when :info
      'alert-info'
    else
      'alert-info'
    end
  end

  def flash_icon(type)
    case type.to_sym
    when :notice, :success
      content_tag :svg, class: 'w-5 h-5 flex-shrink-0', fill: 'currentColor', viewBox: '0 0 20 20' do
        content_tag :path, '', fill_rule: 'evenodd', d: 'M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z', clip_rule: 'evenodd'
      end
    when :alert, :error
      content_tag :svg, class: 'w-5 h-5 flex-shrink-0', fill: 'currentColor', viewBox: '0 0 20 20' do
        content_tag :path, '', fill_rule: 'evenodd', d: 'M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z', clip_rule: 'evenodd'
      end
    when :warning
      content_tag :svg, class: 'w-5 h-5 flex-shrink-0', fill: 'currentColor', viewBox: '0 0 20 20' do
        content_tag :path, '', fill_rule: 'evenodd', d: 'M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z', clip_rule: 'evenodd'
      end
    else
      content_tag :svg, class: 'w-5 h-5 flex-shrink-0', fill: 'currentColor', viewBox: '0 0 20 20' do
        content_tag :path, '', fill_rule: 'evenodd', d: 'M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z', clip_rule: 'evenodd'
      end
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
end
