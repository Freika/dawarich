# frozen_string_literal: true

module IntegrationsHelper
  SERVICE_ICONS = {
    'geocoding' => { name: 'map-pin', library: 'lucide' },
    'immich' => { name: 'immich', library: 'brands' },
    'photoprism' => { name: 'photoprism', library: 'brands' },
    'airtrail' => { name: 'airtrail', library: 'brands' },
    'teslamate' => { name: 'car', library: 'lucide' }
  }.freeze

  def integration_icon(service, css: 'size-5')
    config = SERVICE_ICONS.fetch(service.to_s)

    if config[:library] == 'brands'
      icon config[:name], library: 'brands', class: "#{css} shrink-0"
    else
      icon config[:name], class: "#{css} shrink-0 text-base-content/60"
    end
  end

  def integration_status_icon(status)
    case status
    when :connected
      tag.span(class: 'tooltip tooltip-left', data: { tip: t('settings.integrations.index.status_connected') }) do
        icon 'circle-check', class: 'size-4 text-success'
      end
    when :failed
      tag.span(class: 'tooltip tooltip-left', data: { tip: t('settings.integrations.index.status_failed') }) do
        icon 'circle-alert', class: 'size-4 text-warning'
      end
    end
  end
end
