# frozen_string_literal: true

module PolylinePopupHelpers
  def trigger_polyline_hover_and_get_popup
    # Wait for polylines to be fully loaded
    expect(page).to have_css('.leaflet-overlay-pane', wait: 10)
    sleep 2 # Allow time for polylines to render

    # Try multiple approaches to trigger polyline hover
    popup_content = try_canvas_hover || try_polyline_click || try_map_interaction

    popup_content
  end

  def verify_popup_content_structure(popup_content, distance_unit)
    return false unless popup_content

    # Check for required fields in popup
    required_fields = [
      'Start:',
      'End:',
      'Duration:',
      'Total Distance:',
      'Current Speed:'
    ]

    # Check that all required fields are present
    fields_present = required_fields.all? { |field| popup_content.include?(field) }

    # Check distance unit in Total Distance field
    distance_unit_present = popup_content.include?(distance_unit == 'km' ? 'km' : 'mi')

    # Check speed unit in Current Speed field (should match distance unit)
    speed_unit_present = if distance_unit == 'mi'
                          popup_content.include?('mph')
                        else
                          popup_content.include?('km/h')
                        end

    fields_present && distance_unit_present && speed_unit_present
  end

  def extract_popup_data(popup_content)
    return {} unless popup_content

    data = {}

    # Extract start time
    if match = popup_content.match(/Start:<\/strong>\s*([^<]+)/)
      data[:start] = match[1].strip
    end

    # Extract end time
    if match = popup_content.match(/End:<\/strong>\s*([^<]+)/)
      data[:end] = match[1].strip
    end

    # Extract duration
    if match = popup_content.match(/Duration:<\/strong>\s*([^<]+)/)
      data[:duration] = match[1].strip
    end

    # Extract total distance
    if match = popup_content.match(/Total Distance:<\/strong>\s*([^<]+)/)
      data[:total_distance] = match[1].strip
    end

    # Extract current speed
    if match = popup_content.match(/Current Speed:<\/strong>\s*([^<]+)/)
      data[:current_speed] = match[1].strip
    end

    data
  end

  private

  def try_canvas_hover
    page.evaluate_script(<<~JS)
      return new Promise((resolve) => {
        const polylinesPane = document.querySelector('.leaflet-polylinesPane-pane');
        if (polylinesPane) {
          const canvas = polylinesPane.querySelector('canvas');
          if (canvas) {
            const rect = canvas.getBoundingClientRect();
            const centerX = rect.left + rect.width / 2;
            const centerY = rect.top + rect.height / 2;

            const event = new MouseEvent('mouseover', {
              bubbles: true,
              cancelable: true,
              clientX: centerX,
              clientY: centerY
            });

            canvas.dispatchEvent(event);

            setTimeout(() => {
              const popup = document.querySelector('.leaflet-popup-content');
              resolve(popup ? popup.innerHTML : null);
            }, 1000);
          } else {
            resolve(null);
          }
        } else {
          resolve(null);
        }
      });
    JS
  rescue => e
    Rails.logger.debug "Canvas hover failed: #{e.message}"
    nil
  end

  def try_polyline_click
    # Try to find and click on polyline elements directly
    if page.has_css?('path[stroke]', wait: 2)
      polyline = first('path[stroke]')
      polyline.click if polyline
      sleep 1

      if page.has_css?('.leaflet-popup-content')
        return find('.leaflet-popup-content').native.inner_html
      end
    end
    nil
  rescue => e
    Rails.logger.debug "Polyline click failed: #{e.message}"
    nil
  end

  def try_map_interaction
    # As a fallback, click in the center of the map
    map_element = find('.leaflet-container')
    map_element.click
    sleep 1

    if page.has_css?('.leaflet-popup-content', wait: 2)
      return find('.leaflet-popup-content').native.inner_html
    end
    nil
  rescue => e
    Rails.logger.debug "Map interaction failed: #{e.message}"
    nil
  end
end

RSpec.configure do |config|
  config.include PolylinePopupHelpers, type: :system
end
