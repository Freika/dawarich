# frozen_string_literal: true

module ApplicationHelper
  def show_plan_data_window_alert?
    !DawarichSettings.self_hosted? && current_user&.lite?
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
    current_user&.theme == 'light' ? 'dawarich' : 'dawarich-dark'
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

  def notification_link_color(notification)
    return 'text-gray-600' if notification.read?

    'text-blue-600'
  end

  def speed_text_color(speed)
    return 'text-default' if speed.to_i >= 0

    'text-red-500'
  end

  def point_speed(speed, unit = 'km')
    return speed if speed.to_f <= 0

    kmh = speed.to_f * 3.6
    unit == 'mi' ? (kmh * 0.621371).round(1) : kmh.round(1)
  end

  def speed_label(unit = 'km')
    unit == 'mi' ? 'mph' : 'km/h'
  end

  def onboarding_modal_showable?(user)
    !user.settings&.dig('onboarding_completed')
  end

  def trial_button_class(user)
    return 'btn-error' if user.active_until.blank?

    days_left = (user.active_until.to_date - Time.current.to_date).to_i

    case days_left
    when 5..8
      'btn-info'
    when 2...5
      'btn-warning'
    when 0...2
      'btn-error'
    else
      days_left.negative? ? 'btn-error' : 'btn-success'
    end
  end

  def trial_days_remaining_compact(user)
    expiry = user.active_until
    return 'Expired' if expiry.blank? || expiry.past?

    days_left = [(expiry.to_date - Time.zone.today).to_i, 0].max
    "#{days_left}d left"
  end

  def subscription_upgrade_url(user)
    if user.pending_payment?
      trial_resume_path
    else
      "#{MANAGER_URL}/auth/dawarich?token=#{user.generate_subscription_token}"
    end
  end

  def subscription_button_label(user)
    return 'Finish signup' if user.pending_payment?

    trial_days_remaining_compact(user)
  end

  def subscription_cta_label(user)
    user.pending_payment? ? 'Resume' : 'Subscribe'
  end

  def oauth_provider_name(provider)
    return OIDC_PROVIDER_NAME if provider == :openid_connect

    OmniAuth::Utils.camelize(provider)
  end

  OAUTH_PROVIDERS = {
    google_oauth2: {
      icon_name: 'google',
      label: 'Sign in with Google',
      css_class: 'bg-white text-gray-700 border border-gray-300 hover:bg-gray-50'
    },
    github: {
      icon_name: 'github',
      label: 'Sign in with GitHub',
      css_class: 'bg-[#24292f] text-white hover:bg-[#383f47] border-[#24292f]'
    }
  }.freeze

  def mobile_browser?
    user_agent = request.user_agent.to_s
    user_agent.match?(/iPhone|iPad|iPod|Android/i)
  end

  def visible_omniauth_providers
    providers = resource_class.omniauth_providers
    providers = providers.reject { |p| p == :google_oauth2 } if mobile_browser?
    providers
  end

  def oauth_button_config(provider)
    config = OAUTH_PROVIDERS[provider.to_sym]

    if config
      {
        icon: icon(config[:icon_name], library: 'brands', class: 'size-5'),
        label: config[:label],
        css_class: config[:css_class]
      }
    else
      {
        icon: nil,
        label: "Sign in with #{oauth_provider_name(provider)}",
        css_class: 'btn-primary'
      }
    end
  end

  def email_password_registration_enabled?
    return true unless DawarichSettings.self_hosted?

    DawarichSettings.registration_enabled?
  end

  def email_password_login_enabled?
    return true unless DawarichSettings.oidc_enabled?

    DawarichSettings.registration_enabled?
  end

  def preferred_map_path(params = {})
    signed_in =
      begin
        user_signed_in?
      rescue Devise::MissingWarden
        false
      end
    return map_v2_path(params) unless signed_in

    preferred_version = current_user.safe_settings.maps&.dig('preferred_version')
    preferred_version == 'v1' ? map_v1_path(params) : map_v2_path(params)
  end

  # Generates a user-specific upgrade URL that authenticates the user
  # with the external subscription service via JWT token.
  # Accepts optional UTM parameters for tracking.
  # Returns an empty string on self-hosted instances — there is no
  # upgrade flow there, and the JWT secret is not configured.
  def upgrade_url(utm_source: 'app', utm_medium: nil, utm_campaign: 'lite_upgrade', utm_content: nil)
    return '' if DawarichSettings.self_hosted?

    base = "#{MANAGER_URL}/auth/dawarich?token=#{current_user.generate_subscription_token}"
    utm = { utm_source:, utm_medium:, utm_campaign:, utm_content: }.compact
    utm.any? ? "#{base}&#{utm.to_query}" : base
  end

  def pro_badge_tag(preview: true)
    return unless current_user&.lite?

    tooltip = preview ? 'Available on Pro — click to preview' : 'Available on Pro'
    link_to upgrade_url(utm_medium: 'badge', utm_content: 'pro_badge'),
            target: '_blank', rel: 'noopener noreferrer',
            class: 'tooltip tooltip-bottom', 'data-tip': tooltip, tabindex: '0' do
      tag.span(class: 'badge badge-sm badge-outline gap-1') do
        concat icon('lock', class: 'w-3 h-3')
        concat ' Pro'
      end
    end
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

  STATUS_BADGE_CLASSES = {
    'completed' => 'bg-success/10 text-success',
    'processing' => 'bg-info/10 text-info',
    'created' => 'bg-warning/10 text-warning',
    'failed' => 'bg-error/10 text-error',
    'deleting' => 'bg-warning/10 text-warning'
  }.freeze

  def status_badge(record)
    badge_class = STATUS_BADGE_CLASSES[record.status] || 'bg-base-200 text-base-content/50'

    badge_css = "inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium #{badge_class}"
    badge = content_tag(:span, record.status.capitalize, class: badge_css)

    if record.failed? && record.respond_to?(:error_message) && record.error_message.present?
      error_icon = content_tag(:span, icon('circle-alert', class: %w[w-3.5 h-3.5 text-error]),
                               class: 'tooltip tooltip-left cursor-help inline-flex items-center ml-1',
                               data: { tip: record.error_message })
      safe_join([badge, error_icon])
    else
      badge
    end
  end
end
