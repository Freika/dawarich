# frozen_string_literal: true

require 'rails_helper'
require 'base64'
require 'open3'

RSpec.describe 'Deleted selected points leave the map immediately', type: :request do
  # Replay real endpoint responses through the real selection manager and MVT
  # layer. Only the UI shell, HTTP transport and MapLibre cache are doubles.
  # The cache retains a loaded tile until reloaded, and caches HTTP by URL.
  def delete_on_map(payload)
    script = <<~'JS'
      import { readFileSync } from 'node:fs';
      const files = [
        'maps_maplibre/layers/base_layer',
        'maps_maplibre/layers/heatmap_layer',
        'maps_maplibre/utils/marker_theme',
        'maps_maplibre/utils/tile_freshness',
        'maps_maplibre/utils/layer_dependencies',
        'maps_maplibre/layers/points_mvt_layer',
        'maps_maplibre/layers/selected_points_layer',
        'controllers/maps/maplibre/layer_manager',
        'controllers/maps/maplibre/area_selection_manager',
      ];
      const errors = [];
      const shell = `
        const translate = key => key;
        const Toast = { info() {}, success() {}, error: message => globalThis.uiErrors.push(message) };
        const SettingsManager = { getSettings: () => ({ anomaliesEnabled: false }) };
      `;
      globalThis.uiErrors = errors;
      globalThis.confirm = () => true;
      const source = shell + files.map(file => readFileSync(`app/javascript/${file}.js`, 'utf8')
        .replace(/^import[\s\S]*?from "[^"]+"\n/gm, '')).join('\n');
      const { AreaSelectionManager, LayerManager, SelectedPointsLayer, withTileVersion } =
        await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
      const input = JSON.parse(readFileSync(0, 'utf8'));
      console.log = () => {};
      const sources = new Map(), layers = new Map(), httpCache = new Map();
      let deleted = false, displayedTile, submittedIds;
      function loadTile(config) {
        const path = config.tiles[0].replace('{z}/{x}/{y}', input.tileCoordinates);
        const url = withTileVersion(new URL(path, 'http://127.0.0.1:55460')).href;
        if (!httpCache.has(url)) httpCache.set(url, deleted ? input.afterTile : input.beforeTile);
        displayedTile = httpCache.get(url);
      }
      const map = {
        getSource: id => sources.get(id),
        addSource(id, config) {
          sources.set(id, { ...config, setData() {} });
          if (config.type === 'vector') loadTile(config);
        },
        removeSource: id => sources.delete(id),
        getLayer: id => layers.get(id),
        addLayer: config => layers.set(config.id, config),
        removeLayer: id => layers.delete(id),
        getStyle: () => ({ layers: [...layers.values()] }),
        setLayoutProperty() {}, setPaintProperty() {}, on() {}, off() {},
        refreshTiles: id => loadTile(sources.get(id)),
      };
      const controller = {
        map,
        api: { async bulkDeletePoints(ids) {
          submittedIds = [...ids];
          deleted = true;
          return input.deleteResponse;
        } },
        mapDataManager: { invalidatePoints() {} },
        async loadMapData() { this.layerManager._addPointsMvtLayer(); },
      };
      controller.layerManager = new LayerManager(map, { pointsVisible: true }, controller.api, controller);
      controller.layerManager.pointTileRange = input.range;
      controller.layerManager._addPointsMvtLayer();
      const initialTile = displayedTile;
      const selection = new AreaSelectionManager(controller);
      selection.selectedPointsLayer = new SelectedPointsLayer(map);
      selection.selectedPointsLayer.add({ type: 'FeatureCollection', features: [] });
      selection.selectedPointsLayer.updateSelectedPoints({
        type: 'FeatureCollection', features: input.selectedFeatures,
      });
      selection.selectedAnomalyIds = input.selectedFeatures.map(feature => feature.properties.id);
      await selection[input.deleteMethod]();
      process.stdout.write(JSON.stringify({
        initialTile, displayedTile, submittedIds, errors,
        selectedCount: selection.selectedPointsLayer.getCount(),
      }));
    JS
    stdout, stderr, status = Open3.capture3(
      'node', '--input-type=module', '-e', script,
      stdin_data: JSON.generate(payload), chdir: Rails.root.to_s
    )
    expect(status.success?).to be(true), "JavaScript execution failed: #{stderr}"
    JSON.parse(stdout)
  end

  %w[deleteSelectedPoints deleteSelectedAnomalies].each do |delete_method|
    it "replaces the cached point tile after #{delete_method} without zooming or reloading the page" do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      user = create(:user)
      timestamp = Time.utc(2026, 10, 1, 12).to_i
      # Made-up positions in the open South Pacific, with one unselected control.
      selected = create(:point, user:, longitude: -140.123, latitude: -50.123, timestamp:)
      remaining = create(:point, user:, longitude: -140.122, latitude: -50.123, timestamp: timestamp + 10)
      range = { startAt: '2026-10-01T00:00:00Z', endAt: '2026-10-01T23:59:59Z' }
      x = ((-140.123 + 180) / 360 * 2**12).floor
      latitude_radians = -50.123 * Math::PI / 180
      y = ((1 - Math.asinh(Math.tan(latitude_radians)) / Math::PI) / 2 * 2**12).floor
      tile_coordinates = "12/#{x}/#{y}"
      tile_path = "/api/v1/tiles/points/#{tile_coordinates}.mvt"
      headers = { 'Authorization' => "Bearer #{user.api_key}" }
      tile_params = { start_at: range[:startAt], end_at: range[:endAt] }

      get tile_path, params: tile_params, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.headers['Cache-Control']).to include('max-age=300')
      before_tile = Base64.strict_encode64(response.body)

      delete '/api/v1/points/bulk_destroy', params: { point_ids: [selected.id] }, headers:, as: :json
      expect(response).to have_http_status(:ok)
      delete_response = response.parsed_body
      expect(delete_response.fetch('count')).to eq(1)
      expect(user.points.where(id: selected.id)).not_to exist
      expect(user.points.where(id: remaining.id)).to exist

      get tile_path, params: tile_params, headers: headers
      expect(response).to have_http_status(:ok)
      after_tile = Base64.strict_encode64(response.body)
      expect(after_tile).not_to eq(before_tile)

      result = delete_on_map(
        beforeTile: before_tile, afterTile: after_tile, deleteResponse: delete_response,
        tileCoordinates: tile_coordinates, range:, deleteMethod: delete_method,
        selectedFeatures: [{ type: 'Feature', properties: { id: selected.id },
                             geometry: { type: 'Point', coordinates: [-140.123, -50.123] } }]
      )
      expect(result.fetch('errors')).to be_empty
      expect(result.fetch('submittedIds')).to eq([selected.id])
      expect(result.fetch('selectedCount')).to eq(0)
      expect(result.fetch('initialTile')).to eq(before_tile)
      expect(result.fetch('displayedTile')).to eq(after_tile),
                                               'The backend deleted the point, but its old MVT tile remains on the map'
    end
  end
end
