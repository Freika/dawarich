# frozen_string_literal: true

module ApplicationHelper
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

  def speed_text_color(speed)
    return 'text-default' if speed.to_i >= 0

    'text-red-500'
  end

  def point_speed(speed)
    return speed if speed.to_i <= 0

    speed * 3.6
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

  def trial_days_remaining_compact(user)
    expiry = user.active_until
    return 'Expired' if expiry.blank? || expiry.past?

    days_left = [(expiry.to_date - Time.zone.today).to_i, 0].max
    "#{days_left}d left"
  end

  def oauth_provider_name(provider)
    return OIDC_PROVIDER_NAME if provider == :openid_connect

    OmniAuth::Utils.camelize(provider)
  end

  def email_password_registration_enabled?
    return true unless DawarichSettings.self_hosted?

    ALLOW_EMAIL_PASSWORD_REGISTRATION
  end

  def email_password_login_enabled?
    return true unless DawarichSettings.oidc_enabled?

    ALLOW_EMAIL_PASSWORD_REGISTRATION
  end

  def preferred_map_path(params = {})
    return map_v2_path(params) unless user_signed_in?

    preferred_version = current_user.safe_settings.maps&.dig('preferred_version')
    preferred_version == 'v1' ? map_v1_path(params) : map_v2_path(params)
  end

  def sortable_column(title, column, path_helper, **path_params)
    current_sort = params[:sort_by] || 'created_at'
    current_dir  = params[:order_by] || 'desc'
    is_active    = current_sort == column.to_s
    next_dir     = is_active && current_dir == 'asc' ? 'desc' : 'asc'

    sort_icon = if is_active
                  icon(current_dir == 'asc' ? 'chevron-up' : 'chevron-down', class: 'w-4 h-4 inline-block')
                else
                  icon('arrow-down-up', class: 'w-4 h-4 inline-block opacity-30')
                end

    link_to send(path_helper, **path_params.merge(sort_by: column, order_by: next_dir)),
            class: "inline-flex items-center gap-1 link link-hover#{' font-bold' if is_active}" do
      concat title
      concat sort_icon
    end
  end
end
