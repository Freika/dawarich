# frozen_string_literal: true

module AnalyticsHelper
  # Rybbit 2.8 records a click on an external link as an outbound event with
  # its full URL, so checkout links stay internal (/trial/upgrade) and name the
  # destination without its token. Turbo is off because the redirect leaves
  # the app, and so no hover prefetch mints a token.
  def checkout_link_data(user)
    return { turbo: false } if user.pending_payment?

    { turbo: false, rybbit_event: 'checkout_started', rybbit_prop_destination: "#{MANAGER_URL}/auth/dawarich" }
  end

  # A hidden element that sends one Rybbit event from the browser, so it joins
  # the visitor's session. Cloud only: self-hosted instances load no Rybbit.
  def analytics_event_tag(name, props = {})
    return if DawarichSettings.self_hosted?

    tag.div(hidden: true, data: { controller: 'analytics-event', analytics_event_name_value: name,
                                  analytics_event_props_value: props.to_json })
  end

  # Events a controller queued for the next page, e.g. after a redirect.
  # Reading them clears them, so each is rendered once.
  def queued_analytics_event_tags
    events = session.delete(:analytics_events)
    return if events.blank?

    safe_join(events.map { |event| analytics_event_tag(event['name'], event['props']) })
  end
end
