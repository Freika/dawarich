# frozen_string_literal: true

module MapLayerHelpers
  OVERLAY_LAYERS = [
    'Points',
    'Routes',
    'Fog of War',
    'Heatmap',
    'Scratch map',
    'Areas',
    'Photos',
    'Suggested Visits',
    'Confirmed Visits'
  ].freeze

  def test_layer_toggle(layer_name)
    within('.leaflet-control-layers-expanded') do
      if page.has_content?(layer_name)
        # Find the label that contains the layer name, then find its associated checkbox
        layer_label = find('label', text: layer_name)
        layer_checkbox = layer_label.find('input[type="checkbox"]', visible: false)

        # Get initial state
        initial_checked = layer_checkbox.checked?

        # Toggle the layer by clicking the label (more reliable)
        layer_label.click
        sleep 0.5 # Small delay for layer toggle

        # Verify state changed
        expect(layer_checkbox.checked?).not_to eq(initial_checked)

        # Toggle back
        layer_label.click
        sleep 0.5 # Small delay for layer toggle

        # Verify state returned to original
        expect(layer_checkbox.checked?).to eq(initial_checked)
      end
    end
  end

  def test_base_layer_switching
    within('.leaflet-control-layers-expanded') do
      # Check that we have base layer options (radio buttons)
      expect(page).to have_css('input[type="radio"]')

      # Verify OpenStreetMap is available
      expect(page).to have_content('OpenStreetMap')

      # Test clicking different radio buttons if available
      radio_buttons = all('input[type="radio"]', visible: false)
      expect(radio_buttons.length).to be >= 1

      # Click the first radio button to test layer switching
      if radio_buttons.length > 1
        radio_buttons[1].click
        sleep 1

        # Click back to the first one
        radio_buttons[0].click
        sleep 1
      end
    end
  end
end

RSpec.configure do |config|
  config.include MapLayerHelpers, type: :system
end
