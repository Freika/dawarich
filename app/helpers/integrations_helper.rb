# frozen_string_literal: true

module IntegrationsHelper
  def integration_icon(service, css: 'size-5')
    icon service.to_s, library: 'brands', class: "#{css} shrink-0"
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
