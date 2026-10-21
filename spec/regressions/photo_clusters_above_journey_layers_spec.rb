# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'open3'

RSpec.describe 'Photo clusters above journey layers' do
  # Run the real layer manager and photo/point/track layer implementations.
  # Only unrelated overlays and the MapLibre map are replaced; the map double
  # implements addLayer's insertion order, including beforeId and moveLayer.
  # The visual counterpart is reproduced with Playwright on the running app.
  def layer_order_script
    <<~'JS'
      import fs from 'node:fs';
      import path from 'node:path';
      import vm from 'node:vm';
      const root = path.resolve('app/javascript');
      const actual = new Set([
        'controllers/maps/maplibre/layer_manager',
        ...['base_layer', 'photos_layer', 'points_mvt_layer', 'tracks_mvt_layer', 'heatmap_layer',
          'recent_point_layer', 'replay_marker_layer'].map(n => `maps_maplibre/layers/${n}`),
      ]);
      class UnrelatedLayer { add() {} update() {} }
      const stubs = {
        translate: key => key,
        shouldShowPointPopup: () => false,
        Toast: {}, lazyLoader: {},
        performanceMonitor: {mark() {}, measure() {}},
        SettingsManager: {getSetting: () => '#6366F1'},
        bumpTileVersion() {}, getMarkerStrokeColor: () => '#fff',
        escapeAttribute: String, escapeHtml: String, formatTimestamp: String,
        getCurrentTheme: () => 'light', getThemeColors: () => ({}),
      };
      for (const name of ['Anomalies', 'Areas', 'Family', 'Flights', 'Fog', 'Hexagon', 'Places', 'Tracks', 'Visits']) {
        stubs[`${name}Layer`] = UnrelatedLayer;
      }
      const modules = new Map();
      function load(id) {
        if (modules.has(id)) return modules.get(id);
        const module = actual.has(id)
          ? new vm.SourceTextModule(fs.readFileSync(path.join(root, `${id}.js`), 'utf8'), {identifier: id})
          : new vm.SyntheticModule(Object.keys(stubs), function () {
              for (const [key, value] of Object.entries(stubs)) this.setExport(key, value);
            }, {identifier: id});
        modules.set(id, module);
        return module;
      }
      const entry = load('controllers/maps/maplibre/layer_manager');
      await entry.link((specifier, parent) => load(specifier.startsWith('.')
        ? path.posix.normalize(path.posix.join(path.posix.dirname(parent.identifier), specifier))
        : specifier));
      await entry.evaluate();
      const layers = [];
      const sources = new Map();
      const map = {
        getLayer: id => layers.find(l => l.id === id),
        getStyle: () => ({layers}),
        getSource: id => sources.get(id),
        addSource(id, config) { sources.set(id, {...config, setData() {}}); },
        removeSource: id => sources.delete(id),
        addLayer(layer, beforeId) {
          if (layers.some(l => l.id === layer.id)) throw new Error(`Duplicate layer ${layer.id}`);
          const before = layers.findIndex(l => l.id === beforeId);
          layers.splice(before < 0 ? layers.length : before, 0, layer);
        },
        removeLayer(id) { layers.splice(layers.findIndex(l => l.id === id), 1); },
        moveLayer(id, beforeId) {
          const layer = this.getLayer(id);
          this.removeLayer(id);
          this.addLayer(layer, beforeId);
        },
        setLayoutProperty() {}, setPaintProperty() {},
        querySourceFeatures: () => [], on() {}, off() {},
      };
      const manager = new entry.namespace.LayerManager(map, {
        photosEnabled: true, pointsVisible: true, tracksEnabled: true, heatmapEnabled: true,
      }, {}, {});
      const empty = {type: 'FeatureCollection', features: []};
      const photos = {type: 'FeatureCollection', features: Array.from({length: 12}, (_, id) => ({
        type: 'Feature', geometry: {type: 'Point', coordinates: [-130, -55]}, properties: {id},
      }))};
      await manager.addAllLayers(empty, photos, empty, empty, empty);
      const initial = layers.map(l => l.id);
      manager.updatePointTileRange('2026-10-01T00:00:00Z', '2026-10-01T23:59:59Z');
      const afterDateChange = layers.map(l => l.id);
      await manager.addAllLayers(empty, photos, empty, empty, empty);
      console.log(JSON.stringify({initial, afterDateChange, afterReload: layers.map(l => l.id)}));
    JS
  end

  it 'keeps photo clusters above tracks, heatmap and points but below live markers, including after reloads' do
    stdout, stderr, status = Open3.capture3(
      'node', '--experimental-vm-modules', '--input-type=module', '-e', layer_order_script,
      chdir: File.expand_path('../..', __dir__)
    )
    expect(status.success?).to be(true), "JavaScript harness failed:\n#{stdout}\n#{stderr}"
    orders = JSON.parse(stdout.lines.last)

    aggregate_failures do
      orders.each do |phase, layers|
        %w[photos-clusters photos-cluster-count].each do |photo_layer|
          %w[tracks-mvt points-mvt-heatmap points-mvt].each do |journey_layer|
            message = "#{phase}: #{photo_layer} is obscured by #{journey_layer}; " \
                      "bottom-to-top order: #{layers.join(', ')}"
            expect(layers.index(photo_layer)).to be > layers.index(journey_layer), message
          end
          %w[recent-point-pulse recent-point replay-marker-pulse replay-marker].each do |marker_layer|
            message = "#{phase}: #{photo_layer} covers #{marker_layer}; bottom-to-top order: #{layers.join(', ')}"
            expect(layers.index(photo_layer)).to be < layers.index(marker_layer), message
          end
        end
      end
    end
  end
end
