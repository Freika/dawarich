# frozen_string_literal: true

module PostersHelper
  RENDER_PHASES = {
    'fetching_data' => { label: 'Fetching map data…', step: 1 },
    'drawing_map' => { label: 'Drawing the map…', step: 2 },
    'drawing_route' => { label: 'Drawing your route…', step: 3 },
    'saving' => { label: 'Saving the image…', step: 4 }
  }.freeze

  def poster_render_phase(poster)
    RENDER_PHASES.fetch(poster.settings['progress_phase'], { label: 'Queued…', step: 0 })
  end
end
