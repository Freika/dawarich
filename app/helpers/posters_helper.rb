# frozen_string_literal: true

module PostersHelper
  RENDER_PHASES = {
    'fetching_data' => { label_key: 'fetching_data', step: 1 },
    'drawing_map' => { label_key: 'drawing_map', step: 2 },
    'drawing_route' => { label_key: 'drawing_route', step: 3 },
    'saving' => { label_key: 'saving', step: 4 }
  }.freeze

  def poster_render_phase(poster)
    phase = RENDER_PHASES.fetch(poster.settings['progress_phase'], { label_key: 'queued', step: 0 })
    phase.merge(label: I18n.t("helpers.posters.render_phases.#{phase[:label_key]}"))
  end
end
