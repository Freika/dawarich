# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Issue #2365: emoji map labels' do
  javascript_root = File.expand_path('../../app/javascript', __dir__)
  label_sources = %w[
    maps_maplibre/layers/places_layer.js
    maps_maplibre/layers/areas_layer.js
    maps_maplibre/layers/visits_layer.js
    maps_maplibre/layers/family_layer.js
    controllers/family_map_controller.js
  ]

  it 'records the fix only under 1.16.0 Fixed, without rewriting released history' do
    changelog = File.read(File.expand_path('../../CHANGELOG.md', __dir__))
    release = changelog.split(/^## \[1\.16\.0\][^\n]*\n/, 2).last.split(/^## /, 2).first
    fixed = release.split("### Fixed\n", 2).last.split(/^### /, 2).first

    expect(changelog.lines.grep(/#2365/).size).to eq(1)
    expect(fixed).to include('(#2365).')
  end

  it 'uses supported MapLibre module and marker opacity APIs' do
    source = File.read(File.join(javascript_root, 'maps_maplibre/utils/html_label_manager.js'))

    expect(source).to include('import * as maplibregl from "maplibre-gl"', 'marker.setOpacity(opacity || 1)')
  end

  label_sources.each do |path|
    it "renders names with DOM markers and clears them on teardown in #{path}" do
      source = File.read(File.join(javascript_root, path))

      expect(source).to include('new HtmlLabelManager')
      expect(source).not_to match(/"text-field":\s*\["get", "name"\]/)
      expect(source).to match(/(?:remove|disconnect)\(\)\s*\{[^}]*this\.labels(?:\?|)\.clear\(\)/m)
    end
  end

  %w[controllers/maps/maplibre_controller.js controllers/maps/maplibre/layer_manager.js].each do |path|
    it "does not reference removed symbol labels or unresolved conflicts in #{path}" do
      source = File.read(File.join(javascript_root, path))

      expect(source).not_to include('visits-labels', 'areas-labels', '<<<<<<<', '>>>>>>>')
    end
  end
end
