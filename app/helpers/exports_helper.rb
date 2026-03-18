# frozen_string_literal: true

module ExportsHelper
  FORMAT_STYLES = {
    'json'    => { css: 'bg-primary/10 text-primary', icon: 'earth' },
    'gpx'     => { css: 'bg-success/10 text-success', icon: 'route' },
    'archive' => { css: 'bg-warning/10 text-warning', icon: 'file-up' }
  }.freeze

  def export_format_icon_class(file_format)
    FORMAT_STYLES.dig(file_format, :css) || 'bg-base-200 text-base-content/50'
  end

  def export_format_icon(file_format)
    icon_name = FORMAT_STYLES.dig(file_format, :icon) || 'file-up'
    icon(icon_name, class: 'w-4 h-4')
  end
end
