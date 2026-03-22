# frozen_string_literal: true

module ImportsHelper
  SOURCE_STYLES = {
    'google_semantic_history' => { css: 'bg-error/10 text-error', icon: 'google', library: 'brands' },
    'google_phone_takeout'   => { css: 'bg-error/10 text-error', icon: 'google', library: 'brands' },
    'google_records'         => { css: 'bg-error/10 text-error', icon: 'google', library: 'brands' },
    'gpx'                    => { css: 'bg-success/10 text-success', icon: 'route' },
    'owntracks'              => { css: 'bg-primary/10 text-primary', icon: 'map-pin' },
    'geojson'                => { css: 'bg-warning/10 text-warning', icon: 'earth' },
    'immich_api'             => { css: 'bg-info/10 text-info', icon: 'camera' },
    'photoprism_api'         => { css: 'bg-info/10 text-info', icon: 'camera' },
    'kml'                    => { css: 'bg-warning/10 text-warning', icon: 'earth' },
    'user_data_archive'      => { css: 'bg-base-200 text-base-content/50', icon: 'file-up' }
  }.freeze

  def import_source_icon_class(source)
    SOURCE_STYLES.dig(source, :css) || 'bg-base-200 text-base-content/50'
  end

  def import_source_icon(source)
    style = SOURCE_STYLES[source]
    icon_name = style&.fetch(:icon, 'file-up') || 'file-up'
    library = style&.fetch(:library, nil)

    if library
      icon(icon_name, library: library, class: 'w-4 h-4')
    else
      icon(icon_name, class: 'w-4 h-4')
    end
  end
end
