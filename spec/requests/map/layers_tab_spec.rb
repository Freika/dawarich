# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map layers tab', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  def layers_tab
    get map_v2_path
    Nokogiri::HTML(response.body).at_css('[data-tab-content="layers"]')
  end

  def tile_for(tab, target)
    tab.css(%([data-maps--maplibre-target="#{target}"])).map { _1.ancestors('.layer-tile').first }
  end

  it 'shows every layer as one tile wired to the map controller' do
    tab = layers_tab

    %w[pointsToggle tracksToggle visitsToggle placesToggle areasToggle photosToggle
       heatmapToggle hexagonsToggle fogToggle scratchToggle].each do |target|
      tiles = tile_for(tab, target)

      expect(tiles.size).to eq(1), "expected one tile for #{target}, got #{tiles.size}"
      expect(tiles.first).to be_present, "#{target} is not inside a layer tile"
    end
  end

  it 'describes each tile for assistive technology' do
    input = layers_tab.at_css('[data-maps--maplibre-target="heatmapToggle"]')
    description = input.document.at_css("##{input['aria-describedby']}")

    expect(description.text.strip).to eq(I18n.t('map.maplibre.settings_panel.show_density_heatmap'))
  end

  it 'keeps the per-layer options next to the tiles' do
    tab = layers_tab

    %w[pointsEditToggle visitsSearch placesFilters].each do |target|
      expect(tab.at_css(%([data-maps--maplibre-target="#{target}"]))).to be_present, "#{target} missing"
    end
    expect(tab.css('input[name="fogOfWarMode"]').size).to eq(2)
  end

  it 'offers anomalies as a points option rather than a layer of its own' do
    tab = layers_tab
    points_options = tab.at_css('[data-layer-options="points"]')

    expect(tile_for(tab, 'anomaliesToggle')).to eq([nil])
    expect(points_options.at_css('[data-maps--maplibre-target="anomaliesToggle"]')).to be_present
    expect(points_options.at_css('[data-maps--maplibre-target="pointsEditToggle"]')).to be_present
  end

  it 'groups the fog of war modes as a fog option' do
    fog_options = layers_tab.at_css('[data-layer-options="fog"]')

    expect(fog_options.css('input[name="fogOfWarMode"]').size).to eq(2)
  end

  it 'shows the flights tile only when AirTrail is connected' do
    expect(tile_for(layers_tab, 'flightsToggle')).to be_empty

    user.update!(settings: user.settings.merge('airtrail_url' => 'https://airtrail.example.com'))

    expect(tile_for(layers_tab, 'flightsToggle').size).to eq(1)
  end
end
